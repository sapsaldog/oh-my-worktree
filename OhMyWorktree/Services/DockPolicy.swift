import AppKit

/// Decides the app's Dock visibility (its activation policy) from the two inputs
/// that affect it: whether the user pinned the Dock icon on, and whether a real
/// app window is currently open.
///
/// The app is a menu-bar accessory by default. It must become `.regular` whenever
/// a window is open (so Cmd+Tab and Cmd+` work) *and* whenever the user has opted
/// to always show the Dock icon. Otherwise it stays `.accessory` (no Dock icon).
enum DockPolicy {

    /// `UserDefaults` / `@AppStorage` key backing the "Show icon in Dock" toggle.
    static let defaultsKey = "showInDock"

    /// Resolves the activation policy the app should currently use.
    ///
    /// - Parameters:
    ///   - showInDock: the user's "Show icon in Dock" preference.
    ///   - hasAppWindows: whether a real app window is visible or miniaturized.
    /// - Returns: `.regular` when the Dock icon should show, otherwise `.accessory`.
    static func activationPolicy(
        showInDock: Bool,
        hasAppWindows: Bool
    ) -> NSApplication.ActivationPolicy {
        (showInDock || hasAppWindows) ? .regular : .accessory
    }
}
