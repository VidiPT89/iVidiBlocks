import SwiftUI

/// Design tokens. Every colour is backed by a set in `Assets.xcassets`, so
/// light and dark variants resolve automatically and nothing is hardcoded.
extension Color {
    static let brandOrange = Color("BrandOrange")
    static let brandAmber = Color("BrandAmber")
    static let brandEmber = Color("BrandEmber")
    static let brandInk = Color("BrandInk")

    static let bgPrimary = Color("BgPrimary")
    static let bgSecondary = Color("BgSecondary")
    static let bgElevated = Color("BgElevated")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")

    static func piece(_ type: TetrominoType) -> Color {
        Color(type.colorName)
    }
}

extension ShapeStyle where Self == LinearGradient {
    /// The signature orange to amber sweep used on every primary control.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [.brandOrange, .brandAmber],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }
}

enum Layout {
    static let cornerRadius: CGFloat = 20
    static let cardPadding: CGFloat = 18
    static let minimumTapTarget: CGFloat = 44
}

extension Font {
    /// Rounded display face for titles and anything numeric.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Counters use monospaced digits so they never jitter as they climb.
    static func counter(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// A warm background that shifts with the appearance, used behind every
/// full-screen view so the app feels like one continuous surface.
struct BrandBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color.bgPrimary
            LinearGradient(
                colors: scheme == .dark
                    ? [Color.brandEmber.opacity(0.28), .clear, Color.brandOrange.opacity(0.10)]
                    : [Color.brandAmber.opacity(0.10), .clear, Color.brandOrange.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.brandOrange.opacity(scheme == .dark ? 0.18 : 0.05), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Card surface shared by menu tiles, HUD panels and settings groups.
    func brandCard(cornerRadius: CGFloat = Layout.cornerRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.bgElevated)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.brandOrange.opacity(0.16), lineWidth: 1)
        )
    }
}
