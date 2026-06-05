import AppKit
import SwiftUI

// Tahoe design tokens, ported from the prototype's `colors_and_type.css`.
// Semantic colors resolve per appearance via a dynamic NSColor provider, so they
// track Light/Dark (and the user's Appearance override) without manual branching.

/// Semantic color tokens. Components are 0–255 sRGB; alpha is 0–1.
enum OMWColor {

    private static func dynamic(
        light: (r: Double, g: Double, b: Double, a: Double),
        dark: (r: Double, g: Double, b: Double, a: Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: c.a)
        })
    }

    private static func solid(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    // MARK: Labels
    static let labelPrimary = dynamic(light: (0, 0, 0, 0.85), dark: (255, 255, 255, 0.85))
    static let labelSecondary = dynamic(light: (0, 0, 0, 0.5), dark: (255, 255, 255, 0.55))
    static let labelTertiary = dynamic(light: (0, 0, 0, 0.26), dark: (255, 255, 255, 0.25))
    static let labelQuaternary = dynamic(light: (0, 0, 0, 0.1), dark: (255, 255, 255, 0.1))

    // MARK: Fills
    static let fillPrimary = dynamic(light: (0, 0, 0, 0.1), dark: (255, 255, 255, 0.1))
    static let fillSecondary = dynamic(light: (0, 0, 0, 0.08), dark: (255, 255, 255, 0.08))
    static let fillTertiary = dynamic(light: (0, 0, 0, 0.05), dark: (255, 255, 255, 0.05))
    static let separator = dynamic(light: (0, 0, 0, 0.12), dark: (255, 255, 255, 0.14))

    // MARK: Backgrounds
    static let bgWindow = dynamic(light: (255, 255, 255, 1), dark: (30, 30, 30, 1))
    static let bgGrouped = dynamic(light: (245, 245, 245, 1), dark: (22, 22, 22, 1))
    static let bgRaised = dynamic(light: (255, 255, 255, 1), dark: (44, 44, 46, 1))
    /// Translucent vibrant sidebar fill (sits on the window's glass).
    static let sidebar = dynamic(light: (246, 246, 248, 0.66), dark: (40, 40, 42, 0.62))
    /// Control background (search field, round toolbar buttons, action-bar chips).
    static let controlBg = dynamic(light: (255, 255, 255, 1), dark: (255, 255, 255, 0.1))

    // MARK: System palette (mode-independent)
    static let sysRed = solid(255, 56, 60)
    static let sysOrange = solid(255, 149, 0)
    static let sysYellow = solid(255, 204, 0)
    static let sysGreen = solid(52, 199, 89)
    static let sysPurple = solid(175, 82, 222)
    static let sysGray = solid(142, 142, 147)
    static let onAccent = Color.white

    /// Detached-badge text: darker amber on light for contrast, sys-yellow on dark.
    static let detachedBadgeText = dynamic(light: (160, 123, 0, 1), dark: (255, 204, 0, 1))
}

/// Corner radii (Tahoe "concentric" rounding scale).
enum OMWRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 22
    static let pill: CGFloat = 999
}

extension Font {
    /// Monospaced (SF Mono) — commit hashes, branch names, diff numbers.
    static func omwMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension EnvironmentValues {
    /// The user's chosen accent color, seeded at the window root from the
    /// `accentColorName` preference. Custom token views (selection fill, switches,
    /// focus, the ＋ button) read this; standard controls use `.tint(_:)`.
    @Entry var omwAccent: Color = AccentChoice.default.color
}
