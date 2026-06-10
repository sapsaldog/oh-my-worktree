import AppKit

/// Observes window lifecycle events and dynamically toggles the app's activation policy
/// between `.accessory` (menu-bar-only) and `.regular` (Dock + Cmd+Tab).
///
/// The app switches to `.regular` whenever an app window is visible or miniaturized
/// (so Cmd+` and Cmd+Tab work) *or* whenever the user enabled "Show icon in Dock".
/// When neither holds, it returns to `.accessory` so the Dock icon disappears.
/// The decision itself lives in `DockPolicy`.
@MainActor
final class WindowObserver {

    private var isObserving = false

    /// `true` from a user-initiated update check until Sparkle's update cycle
    /// finishes. Sparkle's result alerts are modal panels that `isAppWindow`
    /// deliberately ignores, so this flag is what keeps the app `.regular`
    /// (and therefore the alert visible) for the duration of the session.
    private var isUpdaterSessionActive = false

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        let center = NotificationCenter.default

        center.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidMiniaturize(_:)),
            name: NSWindow.didMiniaturizeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidDeminiaturize(_:)),
            name: NSWindow.didDeminiaturizeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(showInDockSettingChanged(_:)),
            name: .showInDockSettingChanged,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(updaterSessionStateChanged(_:)),
            name: .updaterSessionStateChanged,
            object: nil
        )
    }

    // MARK: - Notification Handlers

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, isAppWindow(window) else { return }
        updateActivationPolicy()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, isAppWindow(window) else { return }
        // Defer the check so the window has time to actually close
        DispatchQueue.main.async { [weak self] in
            self?.updateActivationPolicy()
        }
    }

    @objc private func windowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, isAppWindow(window) else { return }
        updateActivationPolicy()
    }

    @objc private func windowDidDeminiaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, isAppWindow(window) else { return }
        updateActivationPolicy()
    }

    @objc private func showInDockSettingChanged(_ notification: Notification) {
        updateActivationPolicy()
    }

    @objc private func updaterSessionStateChanged(_ notification: Notification) {
        isUpdaterSessionActive = DockPolicy.updaterSessionActive(from: notification.userInfo)
        updateActivationPolicy()
    }

    // MARK: - Policy Management

    private func updateActivationPolicy() {
        let hasAppWindows = NSApp.windows.contains { window in
            isAppWindow(window) && (window.isVisible || window.isMiniaturized)
        }

        let showInDock = UserDefaults.standard.bool(forKey: DockPolicy.defaultsKey)
        let desiredPolicy = DockPolicy.activationPolicy(
            showInDock: showInDock,
            hasAppWindows: hasAppWindows,
            updaterSessionActive: isUpdaterSessionActive
        )
        let currentPolicy = NSApp.activationPolicy()

        guard desiredPolicy != currentPolicy else { return }

        NSApp.setActivationPolicy(desiredPolicy)

        if desiredPolicy == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Window Filtering

    /// Returns true for real app windows (main window, settings), false for
    /// transient system windows (status bar, popovers, tooltips, etc.).
    private func isAppWindow(_ window: NSWindow) -> Bool {
        let className = String(describing: type(of: window))

        // Filter out known system/transient window types
        let transientTypes = [
            "NSStatusBarWindow",
            "_NSPopoverWindow",
            "NSToolTipPanel",
            "NSMenuWindowManagerWindow",
            "_NSAlertPanel"
        ]
        if transientTypes.contains(className) {
            return false
        }

        // Must have a title bar or be a standard window level
        if window.level != .normal {
            return false
        }

        // Must have standard window style (title bar or closable)
        let hasStandardChrome = window.styleMask.contains(.titled)
        return hasStandardChrome
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension Notification.Name {
    /// Posted when the user toggles "Show icon in Dock". `WindowObserver`
    /// re-evaluates the activation policy in response.
    static let showInDockSettingChanged = Notification.Name("com.ohmyworktree.showInDockSettingChanged")
}
