import AppKit

/// Decides the app's Dock visibility (its activation policy) from the three
/// inputs that affect it: whether the user pinned the Dock icon on, whether a
/// real app window is currently open, and whether a user-initiated Sparkle
/// update session is running.
///
/// The app is a menu-bar accessory by default. It must become `.regular` whenever
/// a window is open (so Cmd+Tab and Cmd+` work) *and* whenever the user has opted
/// to always show the Dock icon. Otherwise it stays `.accessory` (no Dock icon).
///
/// The updater input exists because Sparkle's result alerts ("You're up to
/// date", errors) run as modal panels that `WindowObserver` deliberately does
/// not count as app windows. Without it, the policy would snap back to
/// `.accessory` the moment Sparkle's transient "Checking for updates…" window
/// closes, deactivating the app and leaving the alert invisible behind other
/// apps' windows (macOS 14+ cooperative activation will not re-activate).
enum DockPolicy {

    /// `UserDefaults` / `@AppStorage` key backing the "Show icon in Dock" toggle.
    static let defaultsKey = "showInDock"

    /// `userInfo` key carrying the Boolean session state in
    /// `.updaterSessionStateChanged` notifications.
    static let updaterSessionActiveKey = "updaterSessionActive"

    /// Resolves the activation policy the app should currently use.
    ///
    /// - Parameters:
    ///   - showInDock: the user's "Show icon in Dock" preference.
    ///   - hasAppWindows: whether a real app window is visible or miniaturized.
    ///   - updaterSessionActive: whether a user-initiated update check is in
    ///     progress (from click until Sparkle's update cycle finishes).
    /// - Returns: `.regular` when the Dock icon should show, otherwise `.accessory`.
    static func activationPolicy(
        showInDock: Bool,
        hasAppWindows: Bool,
        updaterSessionActive: Bool
    ) -> NSApplication.ActivationPolicy {
        (showInDock || hasAppWindows || updaterSessionActive) ? .regular : .accessory
    }

    /// Extracts the session state from a `.updaterSessionStateChanged`
    /// notification's `userInfo`, defaulting to `false` for missing or
    /// malformed payloads.
    static func updaterSessionActive(from userInfo: [AnyHashable: Any]?) -> Bool {
        userInfo?[updaterSessionActiveKey] as? Bool ?? false
    }
}
