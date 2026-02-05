import AppKit
import Quartz
import Combine

@MainActor
final class QuickLookManager: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    static let shared = QuickLookManager()

    private var previewItems: [PreviewItem] = []
    private var tempFileURLs: [URL] = []

    // Cache for preview URLs to avoid regenerating temp files
    private var previewURLCache: [UUID: URL] = [:]

    // Track current item for navigation
    private var currentItemID: UUID?

    // Subscription for selectedIndex changes
    private var cancellables = Set<AnyCancellable>()

    // Track if we're currently showing preview (to enable navigation)
    private var isPreviewActive = false

    private override init() {
        super.init()
    }

    private func startNavigationObserver() {
        guard cancellables.isEmpty else { return } // Already observing

        AppState.shared.$selectedIndex
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSelectionChange()
            }
            .store(in: &cancellables)
    }

    private func stopNavigationObserver() {
        cancellables.removeAll()
    }

    private func handleSelectionChange() {
        // Only update if we're actively previewing
        guard isPreviewActive else { return }

        // Get the new selected item
        guard let item = AppState.shared.selectedItem else { return }

        // Skip if it's the same item
        guard item.id != currentItemID else { return }

        // Update the preview for the new item
        updatePreview(item: item)
    }

    // MARK: - Public Methods

    func preview(item: ClipboardItem) {
        currentItemID = item.id
        isPreviewActive = true

        // Start observing navigation changes
        startNavigationObserver()

        // Get or create preview URL (uses cache)
        guard let previewURL = getOrCreatePreviewURL(for: item) else {
            print("[QuickLookManager] Cannot create preview for item type: \(item.contentType)")
            return
        }

        previewItems = [PreviewItem(url: previewURL)]

        // Show Quick Look panel
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            panel.delegate = self
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
    }

    /// Update preview for a new item (used when navigating with arrow keys)
    private func updatePreview(item: ClipboardItem) {
        currentItemID = item.id

        // Get or create preview URL (uses cache)
        guard let previewURL = getOrCreatePreviewURL(for: item) else {
            print("[QuickLookManager] Cannot create preview for item type: \(item.contentType)")
            return
        }

        previewItems = [PreviewItem(url: previewURL)]

        // Just reload data - panel is already visible
        if let panel = QLPreviewPanel.shared() {
            panel.reloadData()
        }
    }

    func toggle(item: ClipboardItem) {
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            // Close the preview
            dismiss()
        } else {
            // Open the preview
            preview(item: item)
        }
    }

    func dismiss() {
        isPreviewActive = false
        stopNavigationObserver()

        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
        currentItemID = nil
        cleanupTempFiles()
        previewURLCache.removeAll()
    }

    // MARK: - Preview URL Creation

    /// Get cached preview URL or create a new one
    private func getOrCreatePreviewURL(for item: ClipboardItem) -> URL? {
        // Check cache first
        if let cachedURL = previewURLCache[item.id] {
            // Verify file still exists
            if FileManager.default.fileExists(atPath: cachedURL.path) {
                return cachedURL
            }
            // Remove stale cache entry
            previewURLCache.removeValue(forKey: item.id)
        }

        // Create new preview URL
        guard let url = createPreviewURL(for: item) else { return nil }

        // Cache it
        previewURLCache[item.id] = url
        return url
    }

    private func createPreviewURL(for item: ClipboardItem) -> URL? {
        switch item.contentType {
        case .image:
            // Use the cached image file directly - it's already a PNG
            if let path = item.imagePath {
                let url = ImageCache.shared.getFullImageURL(path: path)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
                // Fall back to thumbnail
                let thumbURL = ImageCache.shared.getThumbnailURL(path: path)
                if FileManager.default.fileExists(atPath: thumbURL.path) {
                    return thumbURL
                }
            }

        case .file:
            // Use actual file path if available
            if let paths = item.filePaths, let firstPath = paths.first {
                return URL(fileURLWithPath: firstPath)
            }

        case .text:
            // Create temp text file
            if let text = item.textContent {
                return saveTempText(text, id: item.id)
            }

        case .rtf:
            // Create temp RTF file
            if let rtfData = item.rtfData {
                return saveTempData(rtfData, id: item.id, extension: "rtf")
            }

        case .html:
            // Create temp HTML file
            if let html = item.htmlContent {
                return saveTempText(html, id: item.id, extension: "html")
            }
        }

        return nil
    }

    private func saveTempText(_ text: String, id: UUID, extension ext: String = "txt") -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("BetterPasting_\(id.uuidString).\(ext)")

        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            tempFileURLs.append(fileURL)
            return fileURL
        } catch {
            print("[QuickLookManager] Failed to save temp text: \(error)")
            return nil
        }
    }

    private func saveTempData(_ data: Data, id: UUID, extension ext: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("BetterPasting_\(id.uuidString).\(ext)")

        do {
            try data.write(to: fileURL)
            tempFileURLs.append(fileURL)
            return fileURL
        } catch {
            print("[QuickLookManager] Failed to save temp data: \(error)")
            return nil
        }
    }

    private func cleanupTempFiles() {
        for url in tempFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURLs.removeAll()
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index < previewItems.count else { return nil }
        return previewItems[index]
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Let the panel handle its own events
        return false
    }
}

// MARK: - Preview Item Wrapper

final class PreviewItem: NSObject, QLPreviewItem {
    let url: URL

    init(url: URL) {
        self.url = url
        super.init()
    }

    var previewItemURL: URL? { url }
    var previewItemTitle: String? { url.lastPathComponent }
}
