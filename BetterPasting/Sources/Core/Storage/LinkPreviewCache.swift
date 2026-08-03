import Foundation
import AppKit
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

/// Stores downscaled link-preview images (og:image, favicons) on disk.
/// Downscaling uses ImageIO so it is safe to call from background threads.
final class LinkPreviewCache: @unchecked Sendable {
    static let shared = LinkPreviewCache()

    private let cacheDir: URL
    private let memory = NSCache<NSString, NSImage>()

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("BetterPasting/link-previews", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        memory.countLimit = 120
        print("[LinkPreviewCache] Cache directory: \(cacheDir.path)")
    }

    /// Downscale and store image data. `key` should be the source image URL.
    /// Returns the relative filename, or nil if the data isn't a decodable image.
    func store(_ data: Data, key: String, maxDimension: CGFloat) -> String? {
        guard let png = downscaledPNG(from: data, maxDimension: maxDimension) else { return nil }

        let filename = "\(Self.digest(key)).png"
        let path = cacheDir.appendingPathComponent(filename)
        do {
            try png.write(to: path)
            return filename
        } catch {
            print("[LinkPreviewCache] Failed to write \(filename): \(error)")
            return nil
        }
    }

    func loadImage(filename: String) -> NSImage? {
        if let cached = memory.object(forKey: filename as NSString) {
            return cached
        }
        let path = cacheDir.appendingPathComponent(filename)
        guard let image = NSImage(contentsOf: path) else { return nil }
        memory.setObject(image, forKey: filename as NSString)
        return image
    }

    func delete(filename: String) {
        memory.removeObject(forKey: filename as NSString)
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(filename))
    }

    func allFiles() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path)) ?? []
        return contents.filter { $0.hasSuffix(".png") }
    }

    // MARK: - Helpers

    private func downscaledPNG(from data: Data, maxDimension: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return output as Data
    }

    private static func digest(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
