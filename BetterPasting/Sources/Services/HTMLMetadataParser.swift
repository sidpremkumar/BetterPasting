import Foundation

/// Extracts Open Graph / Twitter card / standard metadata from an HTML document.
enum HTMLMetadataParser {

    struct Metadata: Sendable {
        var title: String?
        var summary: String?
        var siteName: String?
        var imageURL: URL?
        var faviconURL: URL?
    }

    // Regexes are immutable and thread-safe once built.
    private static let metaRegex = try! NSRegularExpression(
        pattern: "<meta\\s+[^>]*>", options: [.caseInsensitive]
    )
    private static let linkRegex = try! NSRegularExpression(
        pattern: "<link\\s+[^>]*>", options: [.caseInsensitive]
    )
    private static let attrRegex = try! NSRegularExpression(
        pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))",
        options: []
    )
    private static let titleRegex = try! NSRegularExpression(
        pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive]
    )
    private static let maxTitleLength = 200
    private static let maxSummaryLength = 400

    static func parse(html: String, baseURL: URL) -> Metadata {
        // Everything we care about lives in <head>; stop there to keep parsing cheap.
        let head = headSection(of: html)
        let range = NSRange(head.startIndex..<head.endIndex, in: head)

        var properties: [String: String] = [:]
        var iconHref: String?
        var appleIconHref: String?

        for match in metaRegex.matches(in: head, options: [], range: range) {
            guard let tagRange = Range(match.range, in: head) else { continue }
            let attrs = attributes(in: String(head[tagRange]))

            guard let content = attrs["content"], !content.isEmpty else { continue }
            let key = attrs["property"] ?? attrs["name"] ?? attrs["itemprop"]
            guard let key else { continue }

            let normalizedKey = key.lowercased()
            // First occurrence wins — pages sometimes repeat tags.
            if properties[normalizedKey] == nil {
                properties[normalizedKey] = content
            }
        }

        for match in linkRegex.matches(in: head, options: [], range: range) {
            guard let tagRange = Range(match.range, in: head) else { continue }
            let attrs = attributes(in: String(head[tagRange]))

            guard let rel = attrs["rel"]?.lowercased(), let href = attrs["href"], !href.isEmpty else { continue }
            if rel.contains("apple-touch-icon"), appleIconHref == nil {
                appleIconHref = href
            } else if rel.contains("icon"), iconHref == nil {
                iconHref = href
            }
        }

        var documentTitle: String?
        if let match = titleRegex.firstMatch(in: head, options: [], range: range),
           let titleRange = Range(match.range(at: 1), in: head) {
            documentTitle = String(head[titleRange])
        }

        let title = firstValue(
            in: properties,
            keys: ["og:title", "twitter:title", "title"],
            fallback: documentTitle
        )
        let summary = firstValue(
            in: properties,
            keys: ["og:description", "twitter:description", "description"]
        )
        let siteName = firstValue(
            in: properties,
            keys: ["og:site_name", "application-name", "twitter:site"]
        )
        let imageString = firstValue(
            in: properties,
            keys: ["og:image:secure_url", "og:image:url", "og:image", "twitter:image", "twitter:image:src"]
        )

        return Metadata(
            title: clean(title, limit: maxTitleLength),
            summary: clean(summary, limit: maxSummaryLength),
            siteName: clean(siteName, limit: 80),
            imageURL: resolve(imageString, against: baseURL),
            faviconURL: resolve(appleIconHref ?? iconHref, against: baseURL)
                ?? URL(string: "/favicon.ico", relativeTo: baseURL)?.absoluteURL
        )
    }

    // MARK: - Helpers

    private static func headSection(of html: String) -> String {
        if let end = html.range(of: "</head>", options: [.caseInsensitive]) {
            return String(html[html.startIndex..<end.upperBound])
        }
        // No closing head tag (truncated or malformed) — cap the work anyway.
        return String(html.prefix(200_000))
    }

    private static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)

        for match in attrRegex.matches(in: tag, options: [], range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let name = String(tag[nameRange]).lowercased()

            var value: String?
            for group in 2...4 {
                if let valueRange = Range(match.range(at: group), in: tag) {
                    value = String(tag[valueRange])
                    break
                }
            }
            guard let value else { continue }
            if result[name] == nil {
                result[name] = decodeEntities(value)
            }
        }
        return result
    }

    private static func firstValue(
        in properties: [String: String],
        keys: [String],
        fallback: String? = nil
    ) -> String? {
        for key in keys {
            if let value = properties[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return fallback
    }

    private static func clean(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let collapsed = decodeEntities(value)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "\u{2026}" : collapsed
    }

    private static func resolve(_ string: String?, against baseURL: URL) -> URL? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("data:") else { return nil }

        if trimmed.hasPrefix("//") {
            let scheme = baseURL.scheme ?? "https"
            return URL(string: "\(scheme):\(trimmed)")
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private static let namedEntities: [String: String] = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
        "&apos;": "'", "&nbsp;": " ", "&mdash;": "\u{2014}", "&ndash;": "\u{2013}",
        "&hellip;": "\u{2026}", "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}",
        "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}", "&middot;": "\u{00B7}"
    ]

    /// Single left-to-right pass, so a decoded entity is never decoded a second time
    /// (`&#38;amp;` becomes `&amp;`, not `&`).
    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }

        var result = ""
        result.reserveCapacity(string.count)
        var index = string.startIndex

        while let ampersand = string[index...].firstIndex(of: "&") {
            result.append(contentsOf: string[index..<ampersand])

            // Entities we handle are all short; don't scan the whole string for a ';'.
            let limit = string.index(ampersand, offsetBy: 12, limitedBy: string.endIndex) ?? string.endIndex
            if let semicolon = string[ampersand..<limit].firstIndex(of: ";"),
               let decoded = decodeEntity(String(string[ampersand...semicolon])) {
                result.append(decoded)
                index = string.index(after: semicolon)
            } else {
                result.append("&")
                index = string.index(after: ampersand)
            }
        }

        result.append(contentsOf: string[index...])
        return result
    }

    private static func decodeEntity(_ entity: String) -> String? {
        if let named = namedEntities[entity.lowercased()] { return named }

        guard entity.hasPrefix("&#") else { return nil }
        var digits = entity.dropFirst(2).dropLast()
        let isHex = digits.first == "x" || digits.first == "X"
        if isHex { digits = digits.dropFirst() }

        guard !digits.isEmpty,
              let code = UInt32(digits, radix: isHex ? 16 : 10),
              let scalar = Unicode.Scalar(code) else {
            return nil
        }
        return String(Character(scalar))
    }
}
