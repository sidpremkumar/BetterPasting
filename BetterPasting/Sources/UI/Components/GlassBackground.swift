import SwiftUI

struct GlassBackground: View {
    var cornerRadius: CGFloat = 0

    var body: some View {
        Color.clear
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

#Preview {
    GlassBackground(cornerRadius: 20)
        .frame(width: 300, height: 200)
}
