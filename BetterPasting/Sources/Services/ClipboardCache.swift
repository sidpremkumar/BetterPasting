import Foundation
import Combine

final class ClipboardCache: @unchecked Sendable {
    static let shared = ClipboardCache()

    private var cache: [ClipboardItem] = []
    private let lock = NSLock()
    private let maxCacheSize = 500

    private init() {}

    /// Thread-safe read for UI display
    func getCachedItems() -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        return cache
    }

    /// Insert a new item at the front (thread-safe)
    func insertItem(_ item: ClipboardItem) {
        lock.lock()
        defer { lock.unlock() }

        // Check for duplicate by hash and update timestamp if exists
        if let existingIndex = cache.firstIndex(where: { $0.contentHash == item.contentHash }) {
            var updatedItem = cache.remove(at: existingIndex)
            // Create new item with updated timestamp
            updatedItem = ClipboardItem(
                id: updatedItem.id,
                contentHash: updatedItem.contentHash,
                contentType: updatedItem.contentType,
                textContent: updatedItem.textContent,
                imagePath: updatedItem.imagePath,
                filePaths: updatedItem.filePaths,
                rtfData: updatedItem.rtfData,
                htmlContent: updatedItem.htmlContent,
                sourceBundleID: item.sourceBundleID,
                sourceAppName: item.sourceAppName,
                createdAt: Date(),
                isPinned: updatedItem.isPinned
            )
            cache.insert(updatedItem, at: 0)
        } else {
            cache.insert(item, at: 0)
        }

        // Trim cache to max size
        if cache.count > maxCacheSize {
            cache = Array(cache.prefix(maxCacheSize))
        }
    }

    /// Load items from persistent store
    func loadFromStore() {
        lock.lock()
        defer { lock.unlock() }
        cache = ClipboardStore.shared.fetchRecentItems(limit: maxCacheSize)
        print("[ClipboardCache] Loaded \(cache.count) items from store")
    }

    /// Update pinned status in cache
    func updatePinned(id: UUID, isPinned: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if let index = cache.firstIndex(where: { $0.id == id }) {
            var item = cache[index]
            item.isPinned = isPinned
            cache[index] = item

            // Re-sort to put pinned items first
            cache.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned
                }
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    /// Remove item from cache
    func removeItem(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll { $0.id == id }
    }

    /// Clear all cached items
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    /// Bubble up an item to the top (preserves original source app info)
    func bubbleUp(id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        if let existingIndex = cache.firstIndex(where: { $0.id == id }) {
            var item = cache.remove(at: existingIndex)
            // Update timestamp but keep original source app info
            item = ClipboardItem(
                id: item.id,
                contentHash: item.contentHash,
                contentType: item.contentType,
                textContent: item.textContent,
                imagePath: item.imagePath,
                filePaths: item.filePaths,
                rtfData: item.rtfData,
                htmlContent: item.htmlContent,
                sourceBundleID: item.sourceBundleID,  // Keep original source
                sourceAppName: item.sourceAppName,    // Keep original source
                createdAt: Date(),
                isPinned: item.isPinned
            )
            cache.insert(item, at: 0)
            print("[ClipboardCache] Bubbled up item: \(id)")
        }
    }
}
