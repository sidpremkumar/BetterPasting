import SwiftUI
import AppKit

/// Slack-style unfurl for clipboard items that are a single URL.
/// Falls back to the plain URL text while loading, or when the site has no metadata.
struct LinkPreviewCard: View {
    let url: URL
    let fallbackText: String

    @EnvironmentObject private var appState: AppState
    @State private var preview: LinkPreview?
    @State private var isLoading = false

    private var isEnabled: Bool { appState.preferences.enableLinkPreviews }

    var body: some View {
        Group {
            if let preview, preview.hasContent {
                unfurl(preview)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                plainLink
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: preview)
        .task(id: "\(url.absoluteString)|\(isEnabled)") {
            await loadPreview()
        }
    }

    // MARK: - Unfurl

    private func unfurl(_ preview: LinkPreview) -> some View {
        let image = previewImage
        let showsHero = image.map(Self.suitsHeroBanner) ?? false

        return VStack(alignment: .leading, spacing: 0) {
            if showsHero, let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }

            HStack(alignment: .top, spacing: 8) {
                textContent(preview)

                // Icon-sized artwork reads better beside the text than stretched above it.
                if !showsHero, let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.white.opacity(0.06))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func textContent(_ preview: LinkPreview) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                faviconView
                    .frame(width: 12, height: 12)

                Text(preview.siteName ?? preview.displayHost)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let title = preview.title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            if let summary = preview.summary {
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Wide, reasonably large artwork works as a banner; logos and icons don't.
    private static func suitsHeroBanner(_ image: NSImage) -> Bool {
        let size = image.size
        guard size.width >= 320, size.height > 0 else { return false }
        return size.width / size.height >= 1.2
    }

    @ViewBuilder
    private var faviconView: some View {
        if let filename = preview?.faviconFilename,
           let icon = LinkPreviewCache.shared.loadImage(filename: filename) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "link")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private var previewImage: NSImage? {
        guard let filename = preview?.imageFilename else { return nil }
        return LinkPreviewCache.shared.loadImage(filename: filename)
    }

    // MARK: - Fallback

    private var plainLink: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(fallbackText)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Loading

    private func loadPreview() async {
        guard isEnabled else {
            preview = nil
            isLoading = false
            return
        }
        guard preview == nil else { return }

        isLoading = true
        let fetched = await LinkPreviewService.shared.preview(for: url)
        isLoading = false
        guard !Task.isCancelled else { return }

        preview = fetched
    }
}
