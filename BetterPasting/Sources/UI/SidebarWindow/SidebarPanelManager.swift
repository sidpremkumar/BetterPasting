import AppKit
import Combine

@MainActor
final class SidebarPanelManager {
    static let shared = SidebarPanelManager()

    private var panel: SidebarPanel?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupScreenMonitoring()
    }

    private func setupScreenMonitoring() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleScreenChange()
                }
            }
            .store(in: &cancellables)
    }

    private func handleScreenChange() {
        // If panel is visible, reposition it
        if let panel = panel, panel.isVisible {
            panel.hide()
        }
    }

    // MARK: - Public Methods

    func toggle() {
        if panel == nil {
            panel = SidebarPanel()  // Screen is detected dynamically in show()
        }
        panel?.toggle()
    }

    func show() {
        if panel == nil {
            panel = SidebarPanel()  // Screen is detected dynamically in show()
        }
        panel?.show()
    }

    func hide() {
        panel?.hide()
    }

    func selectNext() {
        panel?.selectNext()
    }

    func selectPrevious() {
        panel?.selectPrevious()
    }

    func copyAtIndex(_ index: Int) {
        let items = AppState.shared.filteredItems
        guard items.indices.contains(index) else { return }

        let item = items[index]
        AppState.shared.selectedIndex = index

        // Trigger copied feedback animation on the row
        NotificationCenter.default.post(name: .triggerCopiedFeedback, object: index)

        // Copy to clipboard and dismiss sidebar after brief delay for feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ClipboardCopier.shared.copyToClipboard(item)
            self.hide()
        }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }
}
