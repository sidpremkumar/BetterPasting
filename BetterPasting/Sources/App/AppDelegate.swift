import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventTap: KeyboardEventTap?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set as accessory app (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Request permissions
        Task {
            await PermissionManager.shared.requestPermissions()
        }

        // Load cached items
        ClipboardCache.shared.loadFromStore()
        AppState.shared.clipboardItems = ClipboardCache.shared.getCachedItems()

        // Start clipboard monitoring
        ClipboardMonitor.shared.startMonitoring()

        // Subscribe to new clipboard items
        ClipboardMonitor.shared.onNewItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.handleNewClipboardItem(item)
            }
            .store(in: &cancellables)

        // Setup event tap for global hotkeys
        setupEventTap()

        // Start periodic cleanup
        CleanupManager.shared.startPeriodicCleanup()

        print("[AppDelegate] Application launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stopMonitoring()
        CleanupManager.shared.stopPeriodicCleanup()
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
        }
    }

    // MARK: - Clipboard Item Handling

    private func handleNewClipboardItem(_ item: ClipboardItem) {
        var savedItem = item

        // Save image to cache if needed
        if item.contentType == .image,
           let content = ContentExtractor.extract(from: NSPasteboard.general),
           let imageData = content.imageData {
            if let path = ImageCache.shared.saveImage(imageData, id: item.id) {
                savedItem = ClipboardItem(
                    id: item.id,
                    contentHash: item.contentHash,
                    contentType: item.contentType,
                    textContent: item.textContent,
                    imagePath: path,
                    filePaths: item.filePaths,
                    rtfData: item.rtfData,
                    htmlContent: item.htmlContent,
                    sourceBundleID: item.sourceBundleID,
                    sourceAppName: item.sourceAppName,
                    createdAt: item.createdAt,
                    isPinned: item.isPinned
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
