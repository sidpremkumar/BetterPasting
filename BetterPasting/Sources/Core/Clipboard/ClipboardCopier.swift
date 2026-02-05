import AppKit

final class ClipboardCopier: @unchecked Sendable {
    static let shared = ClipboardCopier()

    private init() {}

    /// Copy item to clipboard (just write to pasteboard)
    func copyToClipboard(_ item: ClipboardItem) {
        // Suppress clipboard monitoring to avoid re-capturing
        ClipboardMonitor.shared.suppressBriefly()

        // Bubble up the item to the top of history (preserves original source app)
        Task { @MainActor in
            AppState.shared.bubbleUp(id: item.id)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentType {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .image:
            if let path = item.imagePath,
               let image = ImageCache.shared.loadFullImage(path: path),
               let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }

        case .file:
            if let paths = item.filePaths {
                let urls = paths.map { URL(fileURLWithPath: $0) }
                pasteboard.writeObjects(urls as [NSURL])
            }

        case .rtf:
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
                if let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
                    pasteboard.setString(attrString.string, forType: .string)
                }
            }

        case .html:
            if let html = item.htmlContent {
                pasteboard.setString(html, forType: .html)
                let plainText = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                pasteboard.setString(plainText, forType: .string)
            }
        }

        print("[ClipboardCopier] Copied \(item.contentType) to clipboard")
    }

    /// Copy item as plain text (strips all formatting)
    func copyAsPlainText(_ item: ClipboardItem) {
        ClipboardMonitor.shared.suppressBriefly()

        // Bubble up the item to the top of history (preserves original source app)
        Task { @MainActor in
            AppState.shared.bubbleUp(id: item.id)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let plainText: String?

        switch item.contentType {
        case .text:
            plainText = item.textContent

        case .rtf:
            if let rtfData = item.rtfData,
               let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
                plainText = attrString.string
            } else {
                plainText = nil
            }

        case .html:
            if let html = item.htmlContent {
                plainText = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            } else {
                plainText = nil
            }

        case .image, .file:
            plainText = nil
        }

        if let text = plainText {
            pasteboard.setString(text, forType: .string)
            print("[ClipboardCopier] Copied as plain text to clipboard")
        }
    }

    /// Copy item with whitespace trimmed (removes leading/trailing whitespace and collapses newlines)
    func copyTrimmed(_ item: ClipboardItem) {
        ClipboardMonitor.shared.suppressBriefly()

        // Bubble up the item to the top of history (preserves original source app)
        Task { @MainActor in
            AppState.shared.bubbleUp(id: item.id)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let originalText: String?

        switch item.contentType {
        case .text:
            originalText = item.textContent

        case .rtf:
            if let rtfData = item.rtfData,
               let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
                originalText = attrString.string
            } else {
                originalText = nil
            }

        case .html:
            if let html = item.htmlContent {
                originalText = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            } else {
                originalText = nil
            }

        case .image, .file:
            originalText = nil
        }

        if let text = originalText {
            // Remove newlines and collapse multiple spaces
            let trimmed = text
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            pasteboard.setString(trimmed, forType: .string)
            print("[ClipboardCopier] Copied trimmed text to clipboard")
        }
    }
}
