import AppKit
import Combine

/// Payload published when a new clipboard item is detected.
/// Bundles the item metadata with any captured image data so downstream
/// consumers don't need to re-read the (potentially changed) pasteboard.
struct ClipboardCapture: Sendable {
    let item: ClipboardItem
    let imageData: Data?
}

final class ClipboardMonitor: @unchecked Sendable {
    static let shared = ClipboardMonitor()

    let onNewItem = PassthroughSubject<ClipboardCapture, Never>()

    private var lastChangeCount = 0
    private var timer: Timer?
    private var suppressUntil: CFAbsoluteTime = 0
    private let pollInterval: TimeInterval = 0.5

    private init() {}

    func startMonitoring() {
        // Initialize with current change count to avoid capturing existing content
        lastChangeCount = NSPasteboard.general.changeCount
        print("[ClipboardMonitor] Starting with changeCount: \(lastChangeCount)")

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        print("[ClipboardMonitor] Stopped")
    }

    /// Suppress clipboard capture briefly (used when we copy to avoid capturing our own copy)
    func suppressBriefly() {
        // Suppression window must be longer than poll interval to ensure we catch the change
        suppressUntil = CFAbsoluteTimeGetCurrent() + 1.0
        print("[ClipboardMonitor] Suppressing until \(suppressUntil)")
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        // Always update lastChangeCount to avoid re-detecting the same change
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // Skip processing if we're in suppression window (but we still updated lastChangeCount above)
        if CFAbsoluteTimeGetCurrent() < suppressUntil {
            print("[ClipboardMonitor] Suppressed clipboard change")
            return
        }

        // Extract content
        guard let content = ContentExtractor.extract(from: pasteboard) else {
            print("[ClipboardMonitor] No extractable content")
            return
        }

        // Get source app info
        let sourceApp = SourceAppTracker.shared.getFrontmostApp()

        // Create clipboard item
        let item = ClipboardItem(
            id: UUID(),
            contentHash: content.contentHash,
            contentType: content.contentType,
            textContent: content.textContent,
            imagePath: nil,  // Will be set by storage layer if needed
            filePaths: content.filePaths,
            rtfData: content.rtfData,
            htmlContent: content.htmlContent,
            sourceBundleID: sourceApp.bundleID,
            sourceAppName: sourceApp.name,
            createdAt: Date(),
            isPinned: false
        )

        // Bundle item with image data captured NOW (before the pasteboard can change)
        let capture = ClipboardCapture(item: item, imageData: content.imageData)

        print("[ClipboardMonitor] New item: \(content.contentType) from \(sourceApp.name ?? "unknown")")
        onNewItem.send(capture)
    }
}
