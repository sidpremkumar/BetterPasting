import AppKit
import SwiftUI
import Combine

final class SidebarPanel: NSPanel {
    private var hostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private var clickOutsideMonitor: Any?
    private var associatedScreen: NSScreen?

    init(screen: NSScreen? = nil) {
        self.associatedScreen = screen
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configure()
        setupHostingView()
        setupNotifications()
    }

    private func configure() {
        // Window level above everything except screen saver
        level = .popUpMenu

        // Appearance
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Behavior
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        // Appear on all spaces
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient
        ]

        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }

    private func setupHostingView() {
        let sidebarView = SidebarView()
            .environmentObject(AppState.shared)

        hostingView = NSHostingView(rootView: AnyView(sidebarView))
        hostingView?.translatesAutoresizingMaskIntoConstraints = true
        hostingView?.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .copySelectedItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.copySelectedItem()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .quickLookSelectedItem)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                if let item = AppState.shared.selectedItem {
                    QuickLookManager.shared.toggle(item: item)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissSidebar)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hide()
            }
            .store(in: &cancellables)
    }

    // MARK: - Show/Hide

    func show() {
        // Always detect the screen containing the mouse cursor for multi-monitor support
        let screen = Self.screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else { return }
        self.associatedScreen = screen

        // Load items from cache
        let items = ClipboardCache.shared.getCachedItems()
        AppState.shared.clipboardItems = items
        AppState.shared.selectedIndex = 0
        AppState.shared.searchQuery = ""
        AppState.shared.isVisible = true

        // Calculate frame - right edge of screen, full height
        let panelWidth: CGFloat = 360
        let panelHeight = screen.visibleFrame.height

        let startOrigin = CGPoint(
            x: screen.visibleFrame.maxX,  // Start off-screen to the right
            y: screen.visibleFrame.origin.y
        )

        let endOrigin = CGPoint(
            x: screen.visibleFrame.maxX - panelWidth,
            y: screen.visibleFrame.origin.y
        )

        let panelSize = CGSize(width: panelWidth, height: panelHeight)

        // Set initial position (off-screen)
        setFrame(CGRect(origin: startOrigin, size: panelSize), display: false)
        alphaValue = 1
        orderFront(nil)
        makeKey()

        // Animate slide-in from right
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(CGRect(origin: endOrigin, size: panelSize), display: true)
        }

        startClickOutsideMonitor()
        print("[SidebarPanel] Shown with \(items.count) items")
    }

    func hide() {
        stopClickOutsideMonitor()

        // Use the screen where the panel currently is (based on panel's frame)
        let screen = Self.screenContainingPoint(frame.origin) ?? associatedScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else {
            alphaValue = 0
            orderOut(nil)
            AppState.shared.reset()
            return
        }

        let endOrigin = CGPoint(
            x: screen.visibleFrame.maxX,  // Slide off to the right
            y: frame.origin.y
        )

        // Animate slide-out
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrame(CGRect(origin: endOrigin, size: frame.size), display: true)
        } completionHandler: {
            Task { @MainActor in
                self.orderOut(nil)
                AppState.shared.reset()
            }
        }

        print("[SidebarPanel] Hidden")
    }

    func toggle() {
        if AppState.shared.isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Actions

    private func copySelectedItem() {
        guard AppState.shared.selectedItem != nil else { return }

        // Trigger the copy feedback animation
        NotificationCenter.default.post(
            name: .triggerCopyFeedback,
            object: AppState.shared.selectedIndex
        )

        // Copy to clipboard after a brief delay to show feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let item = AppState.shared.selectedItem else { return }
            ClipboardCopier.shared.copyToClipboard(item)

            // Hide sidebar after copying
            self.hide()
        }
    }

    func selectNext() {
        AppState.shared.selectNext()
    }

    func selectPrevious() {
        AppState.shared.selectPrevious()
    }

    // MARK: - Click Outside Monitor

    private func startClickOutsideMonitor() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isVisible else { return }

            let screenLocation = NSEvent.mouseLocation

            // Check if click is inside the panel
            if !self.frame.contains(screenLocation) {
                DispatchQueue.main.async {
                    self.hide()
                }
            }
        }
    }

    private func stopClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Screen Detection

    /// Returns the screen containing the current mouse cursor position
    private static func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    /// Returns the screen containing a specific point
    private static func screenContainingPoint(_ point: CGPoint) -> NSScreen? {
        return NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }
}
