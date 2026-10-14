import SwiftUI

@main
struct BetterPastingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: appState.secureInputHolderName == nil
                  ? "doc.on.clipboard"
                  : "exclamationmark.triangle")
        }
    }
}

struct MenuBarView: View {
    @StateObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let holder = appState.secureInputHolderName {
                Text("⚠️ Hotkey disabled — Secure Keyboard Entry held by \(holder)")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Divider()
            }

            Button("Show Clipboard History") {
                SidebarPanelManager.shared.show()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Divider()

            Text("\(appState.clipboardItems.count) items in history")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Show Link Previews", isOn: Binding(
                get: { appState.preferences.enableLinkPreviews },
                set: { newValue in
                    appState.preferences.enableLinkPreviews = newValue
                    appState.preferences.save()
                }
            ))

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
        // Delete all unpinned items from the database first
        ClipboardStore.shared.deleteUnpinned()

        // Reload cache from the now-cleaned database (only pinned items remain)
        ClipboardCache.shared.clear()
        ClipboardCache.shared.loadFromStore()

        // Sync UI state from the authoritative cache
        appState.clipboardItems = ClipboardCache.shared.getCachedItems()
    }
}
