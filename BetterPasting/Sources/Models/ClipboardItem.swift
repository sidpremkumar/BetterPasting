import Foundation
import AppKit

struct ClipboardItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let contentHash: String
    let contentType: ContentType

    // Content (one of these will be populated based on contentType)
    var textContent: String?
    var imagePath: String?       // Relative path in cache directory
    var filePaths: [String]?     // File URLs as strings
    var rtfData: Data?
    var htmlContent: String?

    // Source app tracking
    let sourceBundleID: String?
    let sourceAppName: String?

    // Timestamps
    var createdAt: Date

    // User flags
    var isPinned: Bool

    // MARK: - Computed Properties

    var relativeTimestamp: String {
        RelativeTimestampFormatter.format(createdAt)
    }

    var displayPreview: String {
        switch contentType {
        case .text:
            return textContent?.prefix(200).description.replacingOccurrences(of: "\n", with: " ") ?? ""
        case .image:
            return "Image"
        case .file:
            if let paths = filePaths, let first = paths.first {
                let url = URL(fileURLWithPath: first)
                if paths.count > 1 {
                    return "\(url.lastPathComponent) + \(paths.count - 1) more"
                }
                return url.lastPathComponent
            }
            return "File"
        case .rtf:
            if let data = rtfData,
               let attrString = NSAttributedString(rtf: data, documentAttributes: nil) {
                return attrString.string.prefix(200).description.replacingOccurrences(of: "\n", with: " ")
            }
            return "Rich Text"
        case .html:
            // Strip HTML tags for preview
            if let html = htmlContent {
                let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                return stripped.prefix(200).description.replacingOccurrences(of: "\n", with: " ")
            }
            return "HTML"
        }
    }

    var searchableText: String {
        switch contentType {
        case .text:
            return textContent ?? ""
        case .image:
            return "image"
        case .file:
            return filePaths?.joined(separator: " ") ?? ""
        case .rtf:
            if let data = rtfData,
               let attrString = NSAttributedString(rtf: data, documentAttributes: nil) {
                return attrString.string
            }
            return ""
        case .html:
            if let html = htmlContent {
                return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            }
            return ""
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Relative Timestamp Formatter

enum RelativeTimestampFormatter {
    static func format(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        switch interval {
        case ..<60:
            return "Just now"
        case 60..<3600:
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        case 3600..<86400:
            let hours = Int(interval / 3600)
            return "\(hours) hr ago"
        case 86400..<604800:
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}
