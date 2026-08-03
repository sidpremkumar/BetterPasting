import Foundation

final class CleanupManager: @unchecked Sendable {
    static let shared = CleanupManager()

    private let store: ClipboardStore
    private let imageCache: ImageCache
    private var cleanupTimer: Timer?

    private init() {
        self.store = ClipboardStore.shared
        self.imageCache = ImageCache.shared
    }

    func startPeriodicCleanup() {
        // Run cleanup on launch
        runCleanup()

        // Schedule cleanup every 6 hours
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.runCleanup()
        }
    }

    func stopPeriodicCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    func runCleanup() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            let prefs = UserPreferences.load()
            let startTime = CFAbsoluteTimeGetCurrent()

            let cutoffDate = Date().addingTimeInterval(-Double(prefs.maxAgeDays) * 24 * 60 * 60)
            let deletedByAge = self.store.deleteOlderThan(cutoffDate)
            let deletedByCount = self.store.deleteExcess(maxCount: prefs.maxItemCount)
            self.cleanupOrphanedImages()
            self.cleanupLinkPreviews()
            self.store.vacuum()

            let totalDeleted = deletedByAge + deletedByCount
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[CleanupManager] Cleanup completed in \(Int(elapsed))ms - deleted \(deletedByAge) by age, \(deletedByCount) by count")

            // If items were deleted, reload the in-memory cache and sync the UI
            if totalDeleted > 0 {
                ClipboardCache.shared.loadFromStore()

                DispatchQueue.main.async {
                    let refreshedItems = ClipboardCache.shared.getCachedItems()
                    AppState.shared.clipboardItems = refreshedItems
                    print("[CleanupManager] Refreshed in-memory cache and UI after cleanup")
                }
            }
        }
    }

    /// Delete image files with no corresponding database entry
    private func cleanupOrphanedImages() {
        let dbPaths = store.fetchAllImagePaths()
        let filePaths = Set(imageCache.getAllImageFiles())

        let orphaned = filePaths.subtracting(dbPaths)
        for path in orphaned {
            imageCache.deleteImage(path: path)
        }

        if !orphaned.isEmpty {
            print("[CleanupManager] Deleted \(orphaned.count) orphaned images")
        }
    }

    /// Drop link previews that haven't been refreshed in a month, plus any
    /// preview images they left behind.
    private func cleanupLinkPreviews() {
        let cutoff = Date().addingTimeInterval(-Self.linkPreviewMaxAge)
        let deleted = store.deleteLinkPreviewsOlderThan(cutoff)

        let referenced = store.fetchAllLinkPreviewImagePaths()
        let onDisk = Set(LinkPreviewCache.shared.allFiles())
        let orphaned = onDisk.subtracting(referenced)
        for filename in orphaned {
            LinkPreviewCache.shared.delete(filename: filename)
        }

        if deleted > 0 || !orphaned.isEmpty {
            print("[CleanupManager] Deleted \(deleted) stale link previews and \(orphaned.count) orphaned preview images")
        }
    }

    private static let linkPreviewMaxAge: TimeInterval = 30 * 24 * 60 * 60
}
