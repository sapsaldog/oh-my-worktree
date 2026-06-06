import AppKit

/// The user's window-appearance preference (Settings → Appearance).
/// `auto` follows the macOS system setting.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    /// The default when no preference is stored — follow the system.
    static let `default`: AppearanceMode = .auto

    /// The `NSAppearance` to apply app-wide; `nil` means follow the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Resolve a stored preference name, falling back to the default.
    static func named(_ name: String?) -> AppearanceMode {
        guard let name, let mode = AppearanceMode(rawValue: name) else { return .default }
        return mode
    }
}
