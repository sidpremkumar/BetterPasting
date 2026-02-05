import SwiftUI

struct KeyCap: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.6))
            .frame(minWidth: 18, minHeight: 16)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
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

#Preview {
    HStack {
        KeyCap(symbol: "1")
        KeyCap(symbol: "2")
        KeyCap(symbol: "0")
    }
    .padding()
    .background(.black)
}
