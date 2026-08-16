import SwiftUI

enum BrandTheme {
    static let cyan = Color(red: 0.12, green: 0.82, blue: 0.93)
    static let blue = Color(red: 0.25, green: 0.48, blue: 0.98)
    static let indigo = Color(red: 0.28, green: 0.27, blue: 0.72)
    static let graphite = Color(red: 0.055, green: 0.075, blue: 0.11)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [blue, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                graphite,
                Color(red: 0.075, green: 0.09, blue: 0.16),
                Color(red: 0.06, green: 0.12, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    func brandCard(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
    }
}
