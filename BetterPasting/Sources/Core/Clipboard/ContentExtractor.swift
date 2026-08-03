import AppKit
import CryptoKit

struct ExtractedContent: Sendable {
    let contentType: ContentType
    let textContent: String?
    let imageData: Data?
    let filePaths: [String]?
    let rtfData: Data?
    let htmlContent: String?
    let contentHash: String
}

enum ContentExtractor {

    /// Extract content from the pasteboard, returning the most appropriate type
    static func extract(from pasteboard: NSPasteboard) -> ExtractedContent? {
        // Check in priority order

        // 1. Files (highest priority - user likely wants to track file copies)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let paths = urls.map { $0.path }
            let hash = computeHash(paths.joined(separator: "\n"))
            return ExtractedContent(
                contentType: .file,
                textContent: nil,
                imageData: nil,
                filePaths: paths,
                rtfData: nil,
                htmlContent: nil,
                contentHash: hash
            )
        }

        // 2. Images
        if let imageData = extractImageData(from: pasteboard) {
            let hash = computeHash(imageData)
            return ExtractedContent(
                contentType: .image,
                textContent: nil,
                imageData: imageData,
                filePaths: nil,
                rtfData: nil,
                htmlContent: nil,
                contentHash: hash
            )
        }

        // 3. RTF (rich text)
        if let rtfData = pasteboard.data(forType: .rtf) {
            let hash = computeHash(rtfData)
            return ExtractedContent(
                contentType: .rtf,
                textContent: nil,
                imageData: nil,
                filePaths: nil,
                rtfData: rtfData,
                htmlContent: nil,
                contentHash: hash
            )
        }

        // 4. HTML
        // When Safari copies a URL, it puts both HTML (e.g. <a href="url">page title</a>)
        // and plain text (the actual URL) on the pasteboard. If the plain text looks like
        // a URL, prefer it over the HTML so the URL is displayed instead of the page title.
        if let html = pasteboard.string(forType: .html), !html.isEmpty {
            if let text = pasteboard.string(forType: .string), !text.isEmpty, looksLikeURL(text) {
                let hash = computeHash(text)
                return ExtractedContent(
                    contentType: .text,
                    textContent: text,
                    imageData: nil,
                    filePaths: nil,
                    rtfData: nil,
                    htmlContent: nil,
                    contentHash: hash
                )
            }
            let hash = computeHash(html)
            return ExtractedContent(
                contentType: .html,
                textContent: nil,
                imageData: nil,
                filePaths: nil,
                rtfData: nil,
                htmlContent: html,
                contentHash: hash
            )
        }

        // 5. Plain text (fallback)
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let hash = computeHash(text)
            return ExtractedContent(
                contentType: .text,
                textContent: text,
                imageData: nil,
                filePaths: nil,
                rtfData: nil,
                htmlContent: nil,
                contentHash: hash
            )
        }

        return nil
    }

    private static func extractImageData(from pasteboard: NSPasteboard) -> Data? {
        // Try PNG first
        if let pngData = pasteboard.data(forType: .png) {
            return pngData
        }

        // Try TIFF
        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let pngData = image.pngData() {
            return pngData
        }

        // Try to create image from pasteboard
        if let image = NSImage(pasteboard: pasteboard),
           let pngData = image.pngData() {
            return pngData
        }

        return nil
    }

    private static func looksLikeURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), !trimmed.contains("\n") else { return false }
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    private static func computeHash(_ string: String) -> String {
        let data = Data(string.utf8)
        return computeHash(data)
    }

    private static func computeHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - NSImage Extension

extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    func thumbnail(maxSize: CGFloat) -> NSImage? {
        let ratio = min(maxSize / size.width, maxSize / size.height)
        guard ratio < 1.0 else { return self }

        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)
        let newImage = NSImage(size: newSize)

        newImage.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()

        return newImage
    }
}
