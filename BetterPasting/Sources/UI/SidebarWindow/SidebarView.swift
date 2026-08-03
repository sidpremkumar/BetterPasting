import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var isSearchFocused: Bool
    @State private var inactivityTimer: Timer?
    @State private var scrollProxy: ScrollViewProxy?

    private let inactivityTimeout: TimeInterval = 20 // seconds

    var body: some View {
        VStack(spacing: 0) {
            // Clipboard items list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // Invisible anchor for reliable scroll-to-top
                        Color.clear
                            .frame(height: 0)
                            .id("scrollTop")

                        ForEach(Array(appState.filteredItems.enumerated()), id: \.element.id) { index, item in
                            ClipboardRowView(
                                item: item,
                                index: index,
                                isSelected: index == appState.selectedIndex,
                                showQuickKey: index < 10,
                                isCommandHeld: appState.isCommandHeld,
                                onSelect: {
                                    appState.selectedIndex = index
                                }
                            )
                            .id(item.id)
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appState.clipboardItems.map(\.id))

                        if appState.filteredItems.isEmpty {
                            emptyStateView
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 36)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                .onAppear {
                    scrollProxy = proxy
                    // Force hide scrollbars at AppKit level
                    DispatchQueue.main.async {
                        hideScrollIndicators()
                    }
                    // Ensure we start at the top
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo("scrollTop", anchor: .top)
                    }
                }
                .onChange(of: appState.selectedIndex) { _, _ in
                    resetInactivityTimer()
                }
            }

            // Bottom section with hints and search bar
            VStack(spacing: 0) {
                Divider()
                    .background(Color.white.opacity(0.1))

                // Search bar - animated from bottom
                if appState.isSearchActive {
                    SearchBarView(query: $appState.searchQuery, isFocused: $isSearchFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                }

                // Keyboard hints footer
                keyboardHintsView
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(Color.black.opacity(0.15))
        }
        .frame(width: 360)
        .frame(maxHeight: .infinity)
        .background(GlassBackground(cornerRadius: 0))
        .onChange(of: appState.isSearchActive) { _, isActive in
            if isActive {
                isSearchFocused = true
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.isSearchActive)
        .onDisappear {
            inactivityTimer?.invalidate()
            inactivityTimer = nil
        }
    }

    private func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: inactivityTimeout, repeats: false) { _ in
            Task { @MainActor in
                scrollToTop()
            }
        }
    }

    private func scrollToTop() {
        appState.selectedIndex = 0
        withAnimation(.easeOut(duration: 0.3)) {
            scrollProxy?.scrollTo("scrollTop", anchor: .top)
        }
    }

    private func hideScrollIndicators() {
        // Find all NSScrollViews and hide their scrollers
        if let window = NSApplication.shared.windows.first(where: { $0 is SidebarPanel }) {
            hideScrollersInView(window.contentView)
        }
    }

    private func hideScrollersInView(_ view: NSView?) {
        guard let view = view else { return }
        if let scrollView = view as? NSScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScroller = nil
            scrollView.horizontalScroller = nil
        }
        for subview in view.subviews {
            hideScrollersInView(subview)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            if appState.searchQuery.isEmpty {
                Text("No clipboard history yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text("Copy something to get started")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text("No matches found")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var keyboardHintsView: some View {
        HStack(spacing: 0) {
            if appState.isSearchActive {
                hintGroup(icon: "arrow.left.square", keys: ["←"], label: "Copy")
                Spacer()
                hintGroup(icon: nil, keys: ["esc"], label: "Cancel")
            } else {
                hintGroup(icon: "arrow.up.arrow.down", keys: ["↑", "↓"], label: "Navigate")
                Spacer()
                hintGroup(icon: "arrow.left.square", keys: ["←"], label: "Copy")
                Spacer()
                hintGroup(icon: "magnifyingglass", keys: ["A-Z"], label: "Search")
                Spacer()
                hintGroup(icon: nil, keys: ["esc"], label: "Close")
            }
        }
        .animation(.easeOut(duration: 0.15), value: appState.isSearchActive)
    }

    private func hintGroup(icon: String?, keys: [String], label: String) -> some View {
        HStack(spacing: 6) {
            // Key caps
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .frame(minWidth: 18, minHeight: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                        )
                }
            }

            // Label
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let copySelectedItem = Notification.Name("copySelectedItem")
    static let quickLookSelectedItem = Notification.Name("quickLookSelectedItem")
    static let dismissSidebar = Notification.Name("dismissSidebar")
    static let triggerCopiedFeedback = Notification.Name("triggerCopiedFeedback")
    static let triggerCopyFeedback = Notification.Name("triggerCopyFeedback")
}
