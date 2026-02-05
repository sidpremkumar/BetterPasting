import Foundation
import AppKit

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cacheDir: URL
    private let thumbnailDir: URL
    private let fullDir: URL

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("BetterPasting/images", isDirectory: true)
        thumbnailDir = cacheDir.appendingPathComponent("thumbnails", isDirectory: true)
        fullDir = cacheDir.appendingPathComponent("full", isDirectory: true)

        // Create directories
        try? fileManager.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: fullDir, withIntermediateDirectories: true)

        print("[ImageCache] Cache directory: \(cacheDir.path)")
    }

    /// Save image data and return the relative path
    func saveImage(_ data: Data, id: UUID) -> String? {
        let filename = "\(id.uuidString).png"
        let fullPath = fullDir.appendingPathComponent(filename)
        let thumbPath = thumbnailDir.appendingPathComponent(filename)

        do {
            // Save full image (only if < 5MB)
            if data.count < 5 * 1024 * 1024 {
                try data.write(to: fullPath)
            }

            // Create and save thumbnail
            if let image = NSImage(data: data),
               let thumbnail = image.thumbnail(maxSize: 200),
               let thumbData = thumbnail.pngData() {
                try thumbData.write(to: thumbPath)
            }

            return filename
        } catch {
            print("[ImageCache] Failed to save image: \(error)")
            return nil
        }
    }

    func loadThumbnail(path: String) -> NSImage? {
        let fullPath = thumbnailDir.appendingPathComponent(path)
        return NSImage(contentsOf: fullPath)
    }

    func loadFullImage(path: String) -> NSImage? {
        let fullPath = fullDir.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: fullPath.path) {
            return NSImage(contentsOf: fullPath)
        }
        // Fall back to thumbnail
        return loadThumbnail(path: path)
    }

    /// Get the URL for the full image file (for Quick Look)
    func getFullImageURL(path: String) -> URL {
        return fullDir.appendingPathComponent(path)
    }

    /// Get the URL for the thumbnail file (for Quick Look fallback)
    func getThumbnailURL(path: String) -> URL {
        return thumbnailDir.appendingPathComponent(path)
    }

    func deleteImage(path: String) {
        let fullPath = fullDir.appendingPathComponent(path)
        let thumbPath = thumbnailDir.appendingPathComponent(path)

        try? FileManager.default.removeItem(at: fullPath)
        try? FileManager.default.removeItem(at: thumbPath)
    }

    func getAllImageFiles() -> [String] {
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(atPath: thumbnailDir.path)) ?? []
        return contents.filter { $0.hasSuffix(".png") }
    }
}
