import Foundation
import CoreGraphics

/// Fetches and caches link metadata ("unfurls") for copied URLs.
///
/// Three layers, in order: in-memory map → SQLite (`link_previews`) → network.
/// Fetches are coalesced per URL, capped in size, and limited in concurrency.
actor LinkPreviewService {
    static let shared = LinkPreviewService()

    private let session: URLSession
    private var memory: [String: LinkPreview] = [:]
    private var inFlight: [String: Task<LinkPreview?, Never>] = [:]
    private var imageRetryAfter: [String: Date] = [:]
    private static let imageRetryInterval: TimeInterval = 60 * 60

    // Concurrency gate
    private let maxConcurrentFetches = 4
    private var activeFetches = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    // Big enough for pages that bury og: tags deep in <head> (YouTube's sit around 690KB).
    // We stop at </head> anyway, so typical pages read only tens of KB.
    private static let maxHTMLBytes = 1024 * 1024
    private static let maxImageBytes = 4 * 1024 * 1024
    private static let previewImageMaxDimension: CGFloat = 800
    private static let faviconMaxDimension: CGFloat = 64

    /// A browser-like User-Agent: many sites only serve Open Graph tags to real browsers.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData  // we do our own caching
        config.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept-Language": "en-US,en;q=0.9"
        ]
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Returns metadata for `url`, fetching it if we don't have a fresh copy.
    /// Returns nil when the URL can't be unfurled (fetch failed, no metadata, not routable).
    func preview(for url: URL) async -> LinkPreview? {
        guard let key = Self.normalizedKey(url) else { return nil }

        if let cached = memory[key], !cached.isStale {
            guard !cached.didFail else { return nil }
            return await retryingImageIfNeeded(cached)
        }

        if let running = inFlight[key] {
            return await running.value
        }

        let task = Task<LinkPreview?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.load(url: url, key: key)
        }
        inFlight[key] = task

        let result = await task.value
        inFlight[key] = nil
        return result
    }

    // MARK: - Loading

    private func load(url: URL, key: String) async -> LinkPreview? {
        if let stored = ClipboardStore.shared.fetchLinkPreview(url: key), !stored.isStale {
            memory[key] = stored
            guard !stored.didFail else { return nil }
            return await retryingImageIfNeeded(stored)
        }

        await acquireSlot()
        let fetched = await fetch(url: url, key: key)
        releaseSlot()

        memory[key] = fetched
        ClipboardStore.shared.saveLinkPreview(fetched)
        return fetched.didFail ? nil : fetched
    }

    private func fetch(url: URL, key: String) async -> LinkPreview {
        let failure = LinkPreview(url: key, didFail: true)
        guard Self.isFetchable(url) else { return failure }

        do {
            let (html, finalURL) = try await fetchHTML(from: url)
            let metadata = HTMLMetadataParser.parse(html: html, baseURL: finalURL)

            var preview = LinkPreview(
                url: key,
                title: metadata.title,
                summary: metadata.summary,
                siteName: metadata.siteName,
                imageURL: metadata.imageURL?.absoluteString
            )

            if let imageURL = metadata.imageURL, Self.isFetchable(imageURL) {
                preview.imageFilename = await downloadImage(
                    from: imageURL, referer: finalURL.absoluteString,
                    maxDimension: Self.previewImageMaxDimension
                )
            }
            if let faviconURL = metadata.faviconURL, Self.isFetchable(faviconURL) {
                preview.faviconFilename = await downloadImage(
                    from: faviconURL, referer: finalURL.absoluteString,
                    maxDimension: Self.faviconMaxDimension
                )
            }

            // Nothing useful found — remember that so we don't refetch on every open.
            guard preview.hasContent else { return failure }
            return preview
        } catch {
            print("[LinkPreviewService] Failed to unfurl \(key): \(error.localizedDescription)")
            return failure
        }
    }

    // MARK: - Networking

    private enum FetchError: Error {
        case badResponse(Int)
        case notHTML
        case undecodable
    }

    /// Downloads the document, stopping at `</head>` or the byte cap — whichever comes first.
    private func fetchHTML(from url: URL) async throws -> (html: String, finalURL: URL) {
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (stream, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else { throw FetchError.badResponse(0) }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.badResponse(http.statusCode) }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.isEmpty || contentType.contains("html") || contentType.contains("xml") else {
            throw FetchError.notHTML
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(64 * 1024)
        var window: [UInt8] = []

        for try await byte in stream {
            bytes.append(byte)

            // Case-insensitive ASCII match on the trailing "</head>".
            window.append(byte | 0x20)
            if window.count > Self.headTerminator.count { window.removeFirst() }
            if window == Self.headTerminator { break }

            if bytes.count >= Self.maxHTMLBytes { break }
        }

        let data = Data(bytes)
        guard let html = Self.decodeHTML(data, contentType: contentType) else {
            throw FetchError.undecodable
        }
        return (html, http.url ?? url)
    }

    /// Image hosts that rate-limit or hotlink-protect (GitHub's card renderer, for one)
    /// hand back an error page instead of an image; those come back as nil and get retried later.
    private func downloadImage(from url: URL, referer: String?, maxDimension: CGFloat) async -> String? {
        do {
            var request = URLRequest(url: url)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            if let referer {
                request.setValue(referer, forHTTPHeaderField: "Referer")
            }

            let (stream, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            if http.expectedContentLength > Int64(Self.maxImageBytes) { return nil }

            var bytes: [UInt8] = []
            bytes.reserveCapacity(64 * 1024)
            for try await byte in stream {
                bytes.append(byte)
                if bytes.count > Self.maxImageBytes { return nil }
            }

            return LinkPreviewCache.shared.store(
                Data(bytes), key: url.absoluteString, maxDimension: maxDimension
            )
        } catch {
            return nil
        }
    }

    /// Re-attempts a preview's image when the page had one but the download failed
    /// (rate limits are usually transient). At most once an hour per URL, and never
    /// a full page refetch.
    private func retryingImageIfNeeded(_ preview: LinkPreview) async -> LinkPreview {
        guard preview.imageFilename == nil,
              let imageString = preview.imageURL,
              let imageURL = URL(string: imageString),
              Self.isFetchable(imageURL) else {
            return preview
        }

        let now = Date()
        if let retryAfter = imageRetryAfter[preview.url], retryAfter > now { return preview }
        imageRetryAfter[preview.url] = now.addingTimeInterval(Self.imageRetryInterval)

        await acquireSlot()
        let filename = await downloadImage(
            from: imageURL, referer: preview.url, maxDimension: Self.previewImageMaxDimension
        )
        releaseSlot()

        guard let filename else { return preview }

        var updated = preview
        updated.imageFilename = filename
        memory[preview.url] = updated
        ClipboardStore.shared.saveLinkPreview(updated)
        return updated
    }

    // MARK: - Concurrency Gate

    private func acquireSlot() async {
        if activeFetches < maxConcurrentFetches {
            activeFetches += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releaseSlot() {
        // Hand the slot straight to the next waiter rather than releasing it.
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            activeFetches = max(0, activeFetches - 1)
        }
    }

    // MARK: - Static Helpers

    private static let headTerminator: [UInt8] = Array("</head>".utf8).map { $0 | 0x20 }

    /// Strips the fragment so `#anchor` variants share one cache entry.
    static func normalizedKey(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return nil
        }
        components.fragment = nil
        components.scheme = scheme
        return components.url?.absoluteString
    }

    /// Blocks non-http(s) schemes and hosts on the local network — a copied intranet
    /// URL shouldn't cause a background request to an internal service.
    static func isFetchable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }

        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") {
            return false
        }
        if host == "::1" || host.hasPrefix("[::1]") { return false }

        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        if octets.count == 4 {
            switch (octets[0], octets[1]) {
            case (10, _), (127, _), (0, _), (169, 254):
                return false
            case (192, 168):
                return false
            case (172, 16...31):
                return false
            default:
                break
            }
        }
        return true
    }

    private static func decodeHTML(_ data: Data, contentType: String) -> String? {
        if let charset = charsetName(in: contentType) {
            let encoding = CFStringConvertEncodingToNSStringEncoding(
                CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            )
            if encoding != kCFStringEncodingInvalidId,
               let decoded = String(data: data, encoding: String.Encoding(rawValue: encoding)) {
                return decoded
            }
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // Truncated multi-byte sequences at the byte cap are expected; decode leniently.
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        return String(decoding: data, as: UTF8.self)
    }

    private static func charsetName(in contentType: String) -> String? {
        guard let range = contentType.range(of: "charset=") else { return nil }
        let value = contentType[range.upperBound...]
            .prefix { !$0.isWhitespace && $0 != ";" }
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return value.isEmpty ? nil : value
    }
}
