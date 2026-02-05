import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ClipboardRowView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let showQuickKey: Bool
    let isCommandHeld: Bool
    let onSelect: () -> Void

    @State private var isHovered = false
    @State private var showCopiedFeedback = false
    @State private var feedbackText = "Copied!"

    var body: some View {
        ZStack(alignment: .trailing) {
            // Main content area - uses full width
            HStack(alignment: .top, spacing: 12) {
                // Source app icon
                sourceAppIcon
                    .frame(width: 32, height: 32)

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    // Top row: App name and timestamp
                    HStack(spacing: 8) {
                        if let appName = item.sourceAppName {
                            Text(appName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(item.relativeTimestamp)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }

                    // Content preview
                    ContentPreviewLarge(item: item)

                    // Feedback indicator
                    if showCopiedFeedback {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                            Text(feedbackText)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.green)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            // Quick key badge - overlays on top, slides in from right
            if showQuickKey {
                quickKeyBadge
                    .padding(.trailing, 14)
                    .opacity(isCommandHeld ? 1 : 0)
                    .offset(x: isCommandHeld ? 0 : 30)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isCommandHeld)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 0)
        )
        .scaleEffect(showCopiedFeedback ? 0.98 : 1.0)
        .animation(.easeOut(duration: 0.15), value: showCopiedFeedback)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .onMouseDown(
            singleClick: {
                onSelect()
            },
            doubleClick: {
                triggerCopyWithFeedback()
                ClipboardCopier.shared.copyToClipboard(item)
                // Dismiss sidebar after copying
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .dismissSidebar, object: nil)
                }
            }
        )
        .contextMenu {
            Button {
                triggerCopyWithFeedback()
                ClipboardCopier.shared.copyToClipboard(item)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .dismissSidebar, object: nil)
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if item.contentType == .text || item.contentType == .rtf || item.contentType == .html {
                Divider()

                Button {
                    triggerCopyWithFeedback()
                    ClipboardCopier.shared.copyAsPlainText(item)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NotificationCenter.default.post(name: .dismissSidebar, object: nil)
                    }
                } label: {
                    Label("Copy as Plain Text", systemImage: "text.alignleft")
                }

                Button {
                    triggerCopyWithFeedback()
                    ClipboardCopier.shared.copyTrimmed(item)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NotificationCenter.default.post(name: .dismissSidebar, object: nil)
                    }
                } label: {
                    Label("Trim and Copy", systemImage: "scissors")
                }
            }

            Divider()

            Button {
                QuickLookManager.shared.preview(item: item)
            } label: {
                Label("Quick Look", systemImage: "eye")
            }

            if item.contentType == .file || item.contentType == .image {
                Divider()

                Button {
                    saveItem()
                } label: {
                    Label("Save to Downloads", systemImage: "arrow.down.to.line")
                }

                Button {
                    saveItemAs()
                } label: {
                    Label("Save As...", systemImage: "folder")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerCopiedFeedback)) { notification in
            if let targetIndex = notification.object as? Int, targetIndex == index {
                triggerCopyWithFeedback()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerCopyFeedback)) { notification in
            if let targetIndex = notification.object as? Int, targetIndex == index {
                triggerCopyWithFeedback()
            }
        }
    }

    // MARK: - Quick Key Badge

    private var quickKeyBadge: some View {
        VStack(spacing: 2) {
            Text("\u{2318}")
                .font(.system(size: 11, weight: .medium))
            Text(quickKeyLabel)
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(width: 44, height: 52)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    // MARK: - Helpers

    private func triggerCopyWithFeedback() {
        feedbackText = "Copied!"
        withAnimation(.easeOut(duration: 0.15)) {
            showCopiedFeedback = true
        }

        // Reset feedback after a delay (copy doesn't dismiss the panel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.15)) {
                showCopiedFeedback = false
            }
        }
    }

    private func saveItem() {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        switch item.contentType {
        case .file:
            // Copy file(s) to Downloads
            if let paths = item.filePaths {
                for path in paths {
                    let sourceURL = URL(fileURLWithPath: path)
                    let destURL = downloadsURL.appendingPathComponent(sourceURL.lastPathComponent)
                    do {
                        // If file exists, create unique name
                        let finalURL = uniqueURL(for: destURL)
                        try FileManager.default.copyItem(at: sourceURL, to: finalURL)
                        print("[ClipboardRowView] Saved file to: \(finalURL.path)")
                        showSavedFeedback()
                    } catch {
                        print("[ClipboardRowView] Failed to save file: \(error)")
                    }
                }
            }

        case .image:
            // Save image to Downloads
            if let path = item.imagePath,
               let image = ImageCache.shared.loadFullImage(path: path) {
                let filename = "BetterPasting_\(item.id.uuidString.prefix(8)).png"
                let destURL = downloadsURL.appendingPathComponent(filename)
                let finalURL = uniqueURL(for: destURL)

                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    do {
                        try pngData.write(to: finalURL)
                        print("[ClipboardRowView] Saved image to: \(finalURL.path)")
                        showSavedFeedback()
                    } catch {
                        print("[ClipboardRowView] Failed to save image: \(error)")
                    }
                }
            }

        default:
            break
        }
    }

    private func saveItemAs() {
        // Capture item properties before async work
        let contentType = item.contentType
        let filePaths = item.filePaths
        let imagePath = item.imagePath
        let itemId = item.id

        DispatchQueue.main.async {
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true

            switch contentType {
            case .file:
                if let paths = filePaths, let firstPath = paths.first {
                    let sourceURL = URL(fileURLWithPath: firstPath)
                    savePanel.nameFieldStringValue = sourceURL.lastPathComponent
                    savePanel.allowedContentTypes = [.item]
                }

            case .image:
                let filename = "BetterPasting_\(itemId.uuidString.prefix(8)).png"
                savePanel.nameFieldStringValue = filename
                savePanel.allowedContentTypes = [.png]

            default:
                return
            }

            let response = savePanel.runModal()
            guard response == .OK, let destURL = savePanel.url else { return }

            switch contentType {
            case .file:
                if let paths = filePaths {
                    for path in paths {
                        let sourceURL = URL(fileURLWithPath: path)
                        do {
                            if FileManager.default.fileExists(atPath: destURL.path) {
                                try FileManager.default.removeItem(at: destURL)
                            }
                            try FileManager.default.copyItem(at: sourceURL, to: destURL)
                            print("[ClipboardRowView] Saved file to: \(destURL.path)")
                            self.showSavedFeedback()
                        } catch {
                            print("[ClipboardRowView] Failed to save file: \(error)")
                        }
                    }
                }

            case .image:
                if let path = imagePath,
                   let image = ImageCache.shared.loadFullImage(path: path) {
                    if let tiffData = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        do {
                            try pngData.write(to: destURL)
                            print("[ClipboardRowView] Saved image to: \(destURL.path)")
                            self.showSavedFeedback()
                        } catch {
                            print("[ClipboardRowView] Failed to save image: \(error)")
                        }
                    }
                }

            default:
                break
            }
        }
    }

    private func uniqueURL(for url: URL) -> URL {
        var resultURL = url
        var counter = 1
        let fileManager = FileManager.default

        while fileManager.fileExists(atPath: resultURL.path) {
            let filename = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let newFilename = "\(filename) (\(counter))"
            resultURL = url.deletingLastPathComponent()
                .appendingPathComponent(newFilename)
                .appendingPathExtension(ext)
            counter += 1
        }

        return resultURL
    }

    private func showSavedFeedback() {
        feedbackText = "Saved!"
        withAnimation(.easeOut(duration: 0.15)) {
            showCopiedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.15)) {
                showCopiedFeedback = false
            }
        }
    }

    private var quickKeyLabel: String {
        if index == 9 {
            return "0"
        }
        return "\(index + 1)"
    }

    @ViewBuilder
    private var sourceAppIcon: some View {
        if let bundleID = item.sourceBundleID,
           let icon = SourceAppTracker.shared.getIcon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: item.contentType.iconName)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
        }
    }

    private var backgroundColor: Color {
        if showCopiedFeedback {
            return Color.green.opacity(0.12)
        } else if isSelected {
            return Color.accentColor.opacity(0.2)
        } else if isHovered {
            return Color.white.opacity(0.08)
        } else {
            return Color.white.opacity(0.04)
        }
    }

    private var borderColor: Color {
        if showCopiedFeedback {
            return Color.green.opacity(0.5)
        } else if isSelected {
            return Color.accentColor.opacity(0.6)
        }
        return Color.clear
    }
}

// MARK: - Large Content Preview

struct ContentPreviewLarge: View {
    let item: ClipboardItem

    var body: some View {
        switch item.contentType {
        case .text, .rtf, .html:
            Text(item.displayPreview)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .image:
            HStack(spacing: 12) {
                if let path = item.imagePath,
                   let image = ImageCache.shared.loadThumbnail(path: path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 80, height: 60)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Image")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("Copied from clipboard")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }

        case .file:
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayPreview)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("File")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Mouse Down Modifier (Instant Click Response)

/// A view modifier that triggers an action immediately on mouse down,
/// bypassing SwiftUI's tap gesture delay when double-tap is also present.
struct MouseDownModifier: ViewModifier {
    let onSingleClick: () -> Void
    let onDoubleClick: (() -> Void)?

    func body(content: Content) -> some View {
        content.overlay(
            MouseDownView(onSingleClick: onSingleClick, onDoubleClick: onDoubleClick)
        )
    }
}

struct MouseDownView: NSViewRepresentable {
    let onSingleClick: () -> Void
    let onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> MouseDownNSView {
        let view = MouseDownNSView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: MouseDownNSView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
}

class MouseDownNSView: NSView {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else if event.clickCount == 1 {
            onSingleClick?()
        }
        super.mouseDown(with: event)
    }
}

extension View {
    func onMouseDown(perform action: @escaping () -> Void) -> some View {
        modifier(MouseDownModifier(onSingleClick: action, onDoubleClick: nil))
    }

    func onMouseDown(singleClick: @escaping () -> Void, doubleClick: @escaping () -> Void) -> some View {
        modifier(MouseDownModifier(onSingleClick: singleClick, onDoubleClick: doubleClick))
    }
}
