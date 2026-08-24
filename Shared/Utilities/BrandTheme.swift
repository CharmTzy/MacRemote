import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Brand colors and adaptive surfaces. Chrome follows the system appearance:
/// white in light mode, neutral near-black in dark mode — deliberately no
/// blue tint. (The remote-viewer video surface stays black in both modes;
/// that's a video backdrop, not chrome.)
enum BrandTheme {
    static let cyan = Color(red: 0.12, green: 0.82, blue: 0.93)
    static let blue = Color(red: 0.25, green: 0.48, blue: 0.98)
    static let indigo = Color(red: 0.28, green: 0.27, blue: 0.72)
    static let graphite = Color(red: 0.055, green: 0.075, blue: 0.11)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [blue, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Page background — white in light mode, neutral near-black in dark.
    static var background: Color {
        #if canImport(UIKit)
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
                : UIColor.white
        })
        #elseif canImport(AppKit)
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)
                : NSColor.white
        })
        #else
        Color.white
        #endif
    }

    /// Card surface, a step offset from the page background.
    static var cardBackground: Color {
        #if canImport(UIKit)
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.115, green: 0.115, blue: 0.125, alpha: 1)
                : UIColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1)
        })
        #elseif canImport(AppKit)
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedRed: 0.115, green: 0.115, blue: 0.125, alpha: 1)
                : NSColor(calibratedWhite: 0.965, alpha: 1)
        })
        #else
        Color(white: 0.96)
        #endif
    }

    /// Subtle page gradient kept for call-site compatibility — now built
    /// from the adaptive neutral surfaces instead of the old dark-blue mix.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [background, cardBackground],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    func brandCard(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(BrandTheme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}
