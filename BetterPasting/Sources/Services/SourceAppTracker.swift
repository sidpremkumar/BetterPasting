import AppKit

struct SourceAppInfo: Sendable {
    let bundleID: String?
    let name: String?
    let icon: NSImage?
}

final class SourceAppTracker: @unchecked Sendable {
    static let shared = SourceAppTracker()

    private let iconCacheDir: URL
    private var memoryCache: [String: NSImage] = [:]
    private let lock = NSLock()

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        iconCacheDir = appSupport.appendingPathComponent("BetterPasting/icons", isDirectory: true)

        try? fileManager.createDirectory(at: iconCacheDir, withIntermediateDirectories: true)
        print("[SourceAppTracker] Icon cache directory: \(iconCacheDir.path)")
    }

    /// Get information about the currently frontmost application
    func getFrontmostApp() -> SourceAppInfo {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return SourceAppInfo(bundleID: nil, name: nil, icon: nil)
        }

        // Cache the icon when we capture it
        if let bundleID = app.bundleIdentifier, let icon = app.icon {
            cacheIcon(icon, for: bundleID)
        }

        return SourceAppInfo(
            bundleID: app.bundleIdentifier,
            name: app.localizedName,
            icon: app.icon
        )
    }

    /// Get the icon for a bundle ID - checks disk cache first, then system
    func getIcon(for bundleID: String) -> NSImage? {
        // Check memory cache first
        lock.lock()
        if let cached = memoryCache[bundleID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Check disk cache
        if let diskCached = loadIconFromDisk(bundleID: bundleID) {
            lock.lock()
            memoryCache[bundleID] = diskCached
            lock.unlock()
            return diskCached
        }

        // Fall back to system lookup
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            cacheIcon(icon, for: bundleID)
            return icon
        }

        return nil
    }

    /// Cache an icon to disk and memory
    private func cacheIcon(_ icon: NSImage, for bundleID: String) {
        lock.lock()
        memoryCache[bundleID] = icon
        lock.unlock()

        // Save to disk asynchronously
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.saveIconToDisk(icon, bundleID: bundleID)
        }
    }

    private func saveIconToDisk(_ icon: NSImage, bundleID: String) {
        let filename = sanitizedFilename(bundleID)
        let filePath = iconCacheDir.appendingPathComponent(filename)

        // Skip if already cached
        if FileManager.default.fileExists(atPath: filePath.path) {
            return
        }

        // Resize to 64x64 for storage efficiency
        guard let resized = icon.resized(to: NSSize(width: 64, height: 64)),
              let data = resized.pngData() else {
            return
        }

        do {
            try data.write(to: filePath)
            print("[SourceAppTracker] Cached icon for \(bundleID)")
        } catch {
            print("[SourceAppTracker] Failed to cache icon: \(error)")
        }
    }

    private func loadIconFromDisk(bundleID: String) -> NSImage? {
        let filename = sanitizedFilename(bundleID)
        let filePath = iconCacheDir.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        return NSImage(contentsOf: filePath)
    }

    private func sanitizedFilename(_ bundleID: String) -> String {
        // Replace invalid filename characters
        let sanitized = bundleID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return "\(sanitized).png"
    }
}

// MARK: - NSImage Extensions

extension NSImage {
    func resized(to targetSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: targetSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
