import SwiftUI

/// The user-selectable accent palette (Settings → Appearance).
///
/// Values and ordering match the Tahoe prototype's `ACCENTS` map: the swatch row
/// is rendered in `allCases` order (Graphite first), and the default tint is
/// Purple. RGB components are 0–255 sRGB, cross-checked against the design.
enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case graphite = "Graphite"
    case blue = "Blue"
    case purple = "Purple"
    case green = "Green"
    case orange = "Orange"
    case pink = "Pink"

    var id: String { rawValue }

    /// The default accent when no preference is stored.
    static let `default`: AccentChoice = .blue

    /// 0–255 sRGB components.
    var rgb: (red: Int, green: Int, blue: Int) {
        switch self {
        case .graphite: return (94, 94, 98)
        case .blue: return (0, 122, 255)
        case .purple: return (124, 58, 237)
        case .green: return (52, 199, 89)
        case .orange: return (255, 149, 0)
        case .pink: return (255, 45, 85)
        }
    }

    /// SwiftUI color for tinting selection, switches, focus rings, and the ＋ button.
    var color: Color {
        Color(
            .sRGB,
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255
        )
    }

    /// Resolve a stored preference name, falling back to the default for unknown
    /// or missing values.
    static func named(_ name: String?) -> AccentChoice {
        guard let name, let choice = AccentChoice(rawValue: name) else { return .default }
        return choice
    }
}
