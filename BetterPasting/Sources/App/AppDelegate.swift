import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventTap: KeyboardEventTap?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set as accessory app (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        if DemoScreenshot.runIfRequested() { return }

        // Request permissions
        Task {
            await PermissionManager.shared.requestPermissions()
        }

        // Load cached items
        ClipboardCache.shared.loadFromStore()
        AppState.shared.clipboardItems = ClipboardCache.shared.getCachedItems()

        // Start clipboard monitoring
        ClipboardMonitor.shared.startMonitoring()

        // Subscribe to new clipboard captures
        ClipboardMonitor.shared.onNewItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] capture in
                self?.handleNewClipboardCapture(capture)
            }
            .store(in: &cancellables)

        // Setup event tap for global hotkeys
        setupEventTap()

        // Warn when Secure Keyboard Entry blocks the hotkey's event tap
        SecureInputMonitor.shared.startMonitoring()

        // Start periodic cleanup
        CleanupManager.shared.startPeriodicCleanup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stopMonitoring()
        CleanupManager.shared.stopPeriodicCleanup()
        SecureInputMonitor.shared.stopMonitoring()
        eventTap?.disable()
        print("[AppDelegate] Application terminating")
    }

    // MARK: - Event Tap Setup

    private func setupEventTap() {
        eventTap = KeyboardEventTap()

        eventTap?.onShortcutTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleShortcutEvent(event)
            }
            .store(in: &cancellables)

        // Sync panel visibility state
        AppState.shared.$isVisible
            .sink { [weak self] visible in
                self?.eventTap?.setPanelVisible(visible)
            }
            .store(in: &cancellables)

        // Sync search active state
        AppState.shared.$isSearchActive
            .sink { [weak self] active in
                self?.eventTap?.setSearchActive(active)
            }
            .store(in: &cancellables)
    }

    private func handleShortcutEvent(_ event: ShortcutEvent) {
        switch event {
        case .togglePanel:
            SidebarPanelManager.shared.toggle()

        case .quickCopy(let index):
            SidebarPanelManager.shared.copyAtIndex(index)

        case .navigateUp:
            SidebarPanelManager.shared.selectPrevious()

        case .navigateDown:
            SidebarPanelManager.shared.selectNext()

        case .confirm:
            NotificationCenter.default.post(name: .copySelectedItem, object: nil)

        case .selectCurrent:
            // Copy current item to clipboard (with animation)
            NotificationCenter.default.post(name: .copySelectedItem, object: nil)

        case .quickLook:
            // Show Quick Look preview for current item
            NotificationCenter.default.post(name: .quickLookSelectedItem, object: nil)

        case .dismiss:
            // If search is active, deactivate it first; otherwise hide panel
            if AppState.shared.isSearchActive {
                AppState.shared.isSearchActive = false
                AppState.shared.searchQuery = ""
            } else {
                SidebarPanelManager.shared.hide()
            }

        case .forceHidePanel:
            // CMD+Tab - always close the panel immediately, regardless of search state
            AppState.shared.isSearchActive = false
            AppState.shared.searchQuery = ""
            SidebarPanelManager.shared.hide()

        case .commandStateChanged(let isPressed):
            AppState.shared.isCommandHeld = isPressed

        case .activateSearch:
            AppState.shared.isSearchActive = true

        case .typeToSearch(let characters):
            // Activate search and seed it with the typed character
            AppState.shared.isSearchActive = true
            AppState.shared.searchQuery += characters
        }
    }

    // MARK: - Clipboard Item Handling

    private func handleNewClipboardCapture(_ capture: ClipboardCapture) {
        var savedItem = capture.item

        // Save image to cache if needed — uses image data captured at detection time
        // to avoid race conditions from re-reading a potentially changed pasteboard
        if capture.item.contentType == .image,
           let imageData = capture.imageData {
            if let path = ImageCache.shared.saveImage(imageData, id: capture.item.id) {
                savedItem = ClipboardItem(
                    id: capture.item.id,
                    contentHash: capture.item.contentHash,
                    contentType: capture.item.contentType,
                    textContent: capture.item.textContent,
                    imagePath: path,
                    filePaths: capture.item.filePaths,
                    rtfData: capture.item.rtfData,
                    htmlContent: capture.item.htmlContent,
                    sourceBundleID: capture.item.sourceBundleID,
                    sourceAppName: capture.item.sourceAppName,
                    createdAt: capture.item.createdAt,
                    isPinned: capture.item.isPinned
                )
            }
        }

        // Add to cache and store
        ClipboardCache.shared.insertItem(savedItem)
        ClipboardStore.shared.insert(savedItem)

        // Update UI
        AppState.shared.addItem(savedItem)

        print("[AppDelegate] Added new item: \(savedItem.contentType)")
    }
}
