import AppKit

/// Observes window lifecycle events and dynamically toggles the app's activation policy
/// between `.accessory` (menu-bar-only) and `.regular` (Dock + Cmd+Tab).
///
/// When at least one app window is visible or miniaturized, the app switches to `.regular`
/// so that Cmd+` and Cmd+Tab work. When all windows are closed, it switches back to `.accessory`
/// so the Dock icon disappears.
@MainActor
final class WindowObserver {

    private var isObserving = false

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

    // MARK: - Policy Management

    private func updateActivationPolicy() {
        let hasAppWindows = NSApp.windows.contains { window in
            isAppWindow(window) && (window.isVisible || window.isMiniaturized)
        }

        let desiredPolicy: NSApplication.ActivationPolicy = hasAppWindows ? .regular : .accessory
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
