import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Panel State

    @Published var isVisible = false
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var selectedIndex = 0
    @Published var searchQuery = "" {
        didSet {
            debounceSearch()
        }
    }
    @Published var isCommandHeld = false  // For showing quick copy hints
    @Published var isSearchActive = false  // For showing/hiding search bar

    /// Name of the app holding Secure Keyboard Entry (blocks the global hotkey), nil when clear
    @Published var secureInputHolderName: String?

    // MARK: - Debounced Search

    @Published private var debouncedSearchQuery = ""
    private var searchDebounceTask: Task<Void, Never>?
    private let searchDebounceDelay: UInt64 = 150_000_000 // 150ms in nanoseconds

    private func debounceSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.searchDebounceDelay ?? 150_000_000)
                guard !Task.isCancelled else { return }
                self?.debouncedSearchQuery = self?.searchQuery ?? ""
                self?.selectedIndex = 0
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    // MARK: - Preferences

    @Published var preferences = UserPreferences.load()

    // MARK: - Computed Properties

    var filteredItems: [ClipboardItem] {
        guard !debouncedSearchQuery.isEmpty else { return clipboardItems }
        return FuzzyMatcher.filter(clipboardItems, query: debouncedSearchQuery)
    }

    var selectedItem: ClipboardItem? {
        let items = filteredItems
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    // MARK: - Navigation

    func selectNext() {
        let maxIndex = filteredItems.count - 1
        guard maxIndex >= 0 else { return }

        if selectedIndex < maxIndex {
            selectedIndex += 1
        }
    }

    func selectPrevious() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func selectIndex(_ index: Int) {
        let maxIndex = filteredItems.count - 1
        guard maxIndex >= 0 else { return }
        selectedIndex = max(0, min(index, maxIndex))
    }

    // MARK: - Reset

    func reset() {
        isVisible = false
        selectedIndex = 0
        searchDebounceTask?.cancel()
        searchQuery = ""
        debouncedSearchQuery = ""
        isCommandHeld = false
        isSearchActive = false
    }

    // MARK: - Item Management

    func addItem(_ item: ClipboardItem) {
        // Deduplicate: if an item with the same content hash already exists,
        // remove it first so we don't show duplicates in the UI
        if let existingIndex = clipboardItems.firstIndex(where: { $0.contentHash == item.contentHash }) {
            let existing = clipboardItems.remove(at: existingIndex)
            // Preserve pinned status from the existing item
            var deduplicatedItem = item
            deduplicatedItem.isPinned = existing.isPinned
            clipboardItems.insert(deduplicatedItem, at: 0)
        } else {
            clipboardItems.insert(item, at: 0)
        }

        // Re-sort to respect pinned items
        clipboardItems.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return lhs.createdAt > rhs.createdAt
        }

        // Keep list bounded
        if clipboardItems.count > 500 {
            clipboardItems = Array(clipboardItems.prefix(500))
        }
    }

    func togglePinned(id: UUID) {
        if let index = clipboardItems.firstIndex(where: { $0.id == id }) {
            clipboardItems[index].isPinned.toggle()

            // Re-sort to put pinned items first
            clipboardItems.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned
                }
                return lhs.createdAt > rhs.createdAt
            }

            // Persist change
            ClipboardStore.shared.togglePinned(id: id, isPinned: clipboardItems[index].isPinned)
            ClipboardCache.shared.updatePinned(id: id, isPinned: clipboardItems[index].isPinned)
        }
    }

    func deleteItem(id: UUID) {
        clipboardItems.removeAll { $0.id == id }
        ClipboardStore.shared.delete(id: id)
        ClipboardCache.shared.removeItem(id: id)
    }

    /// Bubble up an item to the top (preserves original source app info)
    func bubbleUp(id: UUID) {
        guard let index = clipboardItems.firstIndex(where: { $0.id == id }) else { return }

        // Animate the reordering with a smooth spring animation
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            var item = clipboardItems.remove(at: index)
            item.createdAt = Date()
            // Keep original source app info - don't modify sourceBundleID or sourceAppName
            clipboardItems.insert(item, at: 0)

            // Re-sort to respect pinned items
            clipboardItems.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned
                }
                return lhs.createdAt > rhs.createdAt
            }
        }

        // Persist changes (outside animation block for performance)
        ClipboardStore.shared.bubbleUp(id: id)
        ClipboardCache.shared.bubbleUp(id: id)
    }
}
