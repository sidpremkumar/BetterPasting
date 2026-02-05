import Foundation

enum ContentType: String, Codable, CaseIterable, Sendable {
    case text
    case image
    case file
    case rtf
    case html

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .file: return "File"
        case .rtf: return "Rich Text"
        case .html: return "HTML"
        }
    }

    var iconName: String {
        switch self {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        case .rtf: return "doc.richtext"
        case .html: return "chevron.left.forwardslash.chevron.right"
        }
    }
}
