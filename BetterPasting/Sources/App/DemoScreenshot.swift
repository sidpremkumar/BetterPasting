import AppKit
import SwiftUI

/// Temporary utility: `BetterPasting --demo-screenshot <output.png>` seeds the
/// sidebar with fake clipboard items, renders it, and writes a composited PNG.
/// Not wired into any user-facing flow.
@MainActor
enum DemoScreenshot {
    static func runIfRequested() -> Bool {
        guard let idx = CommandLine.arguments.firstIndex(of: "--demo-screenshot") else { return false }
        let outPath = CommandLine.arguments.indices.contains(idx + 1)
            ? CommandLine.arguments[idx + 1]
            : NSTemporaryDirectory() + "betterpasting-demo.png"
        run(outputPath: outPath)
        return true
    }

    private static func run(outputPath: String) {
        AppState.shared.preferences.enableLinkPreviews = true
        seedDemoItems()
        SidebarPanelManager.shared.show()

        // Resize the panel to a README-friendly aspect after the slide-in animation.
        // Use the panel's own animator-free frame set once the show() animation is done.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let panel = NSApp.windows.first(where: { $0 is SidebarPanel }) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    panel.animator().setFrame(NSRect(x: 200, y: 100, width: 360, height: 720), display: true)
                }
                panel.contentView?.layoutSubtreeIfNeeded()
            }
        }

        // Give the link preview time to fetch, then capture and exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            capture(outputPath: outputPath)
            NSApp.terminate(nil)
        }
    }

    // MARK: - Fake data

    private static func seedDemoItems() {
        let now = Date()

        func make(_ type: ContentType,
                  text: String? = nil,
                  imagePath: String? = nil,
                  files: [String]? = nil,
                  bundle: String?,
                  app: String?,
                  secondsAgo: TimeInterval,
                  pinned: Bool = false) -> ClipboardItem {
            ClipboardItem(
                id: UUID(),
                contentHash: UUID().uuidString,
                contentType: type,
                textContent: text,
                imagePath: imagePath,
                filePaths: files,
                rtfData: nil,
                htmlContent: nil,
                sourceBundleID: bundle,
                sourceAppName: app,
                createdAt: now.addingTimeInterval(-secondsAgo),
                isPinned: pinned
            )
        }

        let imageID = UUID()
        let demoImagePath = makeDemoImage(id: imageID)

        let items: [ClipboardItem] = [
            make(.text,
                 text: "https://github.com/apple/swift",
                 bundle: "com.apple.Safari", app: "Safari",
                 secondsAgo: 40),
            make(.text,
                 text: "git rebase -i HEAD~3",
                 bundle: "com.apple.Terminal", app: "Terminal",
                 secondsAgo: 60 * 4),
            make(.image,
                 imagePath: demoImagePath,
                 bundle: "com.apple.finder", app: "Finder",
                 secondsAgo: 60 * 12),
            make(.text,
                 text: "func fibonacci(_ n: Int) -> Int {\n    n < 2 ? n : fibonacci(n - 1) + fibonacci(n - 2)\n}",
                 bundle: "com.apple.dt.Xcode", app: "Xcode",
                 secondsAgo: 60 * 28),
            make(.file,
                 files: ["/Users/demo/Documents/Design Brief.pdf"],
                 bundle: "com.apple.finder", app: "Finder",
                 secondsAgo: 3600 * 2),
            make(.text,
                 text: "Meeting notes — ship v1.0 on Friday 🚀",
                 bundle: "com.apple.Notes", app: "Notes",
                 secondsAgo: 3600 * 5, pinned: true),
        ]

        // Insert oldest-first so the cache's recency ordering matches
        for item in items.reversed() {
            ClipboardCache.shared.insertItem(item)
        }
    }

    private static func makeDemoImage(id: UUID) -> String? {
        let size = NSSize(width: 400, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor.systemIndigo, NSColor.systemTeal])?
            .draw(in: NSRect(origin: .zero, size: size), angle: 45)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return ImageCache.shared.saveImage(png, id: id)
    }

    // MARK: - Capture

    private static func capture(outputPath: String) {
        guard let panel = NSApp.windows.first(where: { $0 is SidebarPanel }),
              let content = panel.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            FileHandle.standardError.write(Data("[DemoScreenshot] capture failed\n".utf8))
            return
        }
        content.cacheDisplay(in: content.bounds, to: rep)

        let panelImage = NSImage(size: content.bounds.size)
        panelImage.addRepresentation(rep)

        // Composite the panel over a desktop-like gradient with a drop shadow
        let panelSize = content.bounds.size
        let margin: CGFloat = 60
        let canvasSize = NSSize(width: panelSize.width + margin * 2,
                                height: panelSize.height + margin * 2)
        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.30, alpha: 1),
            NSColor(calibratedRed: 0.36, green: 0.20, blue: 0.52, alpha: 1),
            NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.50, alpha: 1),
        ])?.draw(in: NSRect(origin: .zero, size: canvasSize), angle: 60)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.set()

        let panelRect = NSRect(x: margin, y: margin, width: panelSize.width, height: panelSize.height)
        let clipPath = NSBezierPath(roundedRect: panelRect, xRadius: 14, yRadius: 14)
        NSGraphicsContext.current?.saveGraphicsState()
        clipPath.addClip()
        panelImage.draw(in: panelRect)
        NSGraphicsContext.current?.restoreGraphicsState()

        canvas.unlockFocus()

        guard let canvasTiff = canvas.tiffRepresentation,
              let canvasRep = NSBitmapImageRep(data: canvasTiff),
              let pngData = canvasRep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("[DemoScreenshot] encode failed\n".utf8))
            return
        }

        do {
            try pngData.write(to: URL(fileURLWithPath: outputPath))
            print("[DemoScreenshot] Wrote \(outputPath)")
        } catch {
            FileHandle.standardError.write(Data("[DemoScreenshot] write failed: \(error)\n".utf8))
        }
    }
}
