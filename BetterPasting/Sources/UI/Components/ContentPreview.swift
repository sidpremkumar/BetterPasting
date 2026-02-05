import SwiftUI
import AppKit

struct ContentPreview: View {
    let item: ClipboardItem

    var body: some View {
        switch item.contentType {
        case .text, .rtf, .html:
            Text(item.displayPreview)
                .foregroundStyle(.primary)
                .lineLimit(2)

        case .image:
            HStack(spacing: 6) {
                if let path = item.imagePath,
                   let image = ImageCache.shared.loadThumbnail(path: path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }

                Text("Image")
                    .foregroundStyle(.secondary)
            }

        case .file:
            HStack(spacing: 6) {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.secondary)

                Text(item.displayPreview)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }
}
