import Foundation

/// Metadata unfurled from a URL (Open Graph / Twitter card / <title>).
struct LinkPreview: Sendable, Hashable {
    /// Normalized absolute URL this preview describes. Doubles as the cache key.
    let url: String
    var title: String?
    var summary: String?
    var siteName: String?
    /// The og:image address we found. Kept even when the download failed, so the
    /// image can be retried without refetching the page.
    var imageURL: String?
    var imageFilename: String?    // Relative filename in LinkPreviewCache
    var faviconFilename: String?  // Relative filename in LinkPreviewCache
    var fetchedAt: Date
    var didFail: Bool

    init(
        url: String,
        title: String? = nil,
        summary: String? = nil,
        siteName: String? = nil,
        imageURL: String? = nil,
        imageFilename: String? = nil,
        faviconFilename: String? = nil,
        fetchedAt: Date = Date(),
        didFail: Bool = false
    ) {
        self.url = url
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.imageURL = imageURL
        self.imageFilename = imageFilename
        self.faviconFilename = faviconFilename
        self.fetchedAt = fetchedAt
        self.didFail = didFail
    }

    // MARK: - Freshness

    static let successTTL: TimeInterval = 7 * 24 * 60 * 60  // 1 week
    static let failureTTL: TimeInterval = 6 * 60 * 60       // retry failures after 6 hours

    var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > (didFail ? Self.failureTTL : Self.successTTL)
    }

    /// True when there is something worth showing beyond the raw URL text.
    var hasContent: Bool {
        !(title?.isEmpty ?? true) || !(summary?.isEmpty ?? true) || imageFilename != nil
    }

    var displayHost: String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

// MARK: - Link Detection

enum LinkDetector {
    /// Returns a URL when the text is nothing but a single http(s) link.
    static func url(in text: String?) -> URL? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8, trimmed.count <= 2048 else { return nil }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }

        let lower = trimmed.lowercased()
        let candidate: String
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            candidate = trimmed
        } else if lower.hasPrefix("www.") {
            candidate = "https://" + trimmed
        } else {
            return nil
        }

        guard let url = URL(string: candidate),
              let host = url.host,
              host.contains("."),
              !host.hasSuffix(".") else {
            return nil
        }
        return url
    }
}

extension ClipboardItem {
    /// The single URL this item represents, if the copied text is nothing but a link.
    var detectedURL: URL? {
        guard contentType == .text else { return nil }
        return LinkDetector.url(in: textContent)
    }
}
