import SwiftUI

@main
struct BetterPastingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("BetterPasting", systemImage: "doc.on.clipboard") {
            MenuBarView()
        }
    }
}

struct MenuBarView: View {
    @StateObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Show Clipboard History") {
                SidebarPanelManager.shared.show()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Divider()

            Text("\(appState.clipboardItems.count) items in history")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Clear History") {
                clearHistory()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 4)
    }

    private func clearHistory() {
        // Keep pinned items
        let pinnedItems = appState.clipboardItems.filter { $0.isPinned }
        appState.clipboardItems = pinnedItems
        ClipboardCache.shared.clear()
        ClipboardCache.shared.loadFromStore()
    }
}
