import AppKit
import SwiftUI

// MARK: - Window Management

extension AppDelegate {
    private static let mainWindowMinimumSize = NSSize(width: 860, height: 520)

    static func configureMainWindowChrome(_ window: NSWindow) {
        window.title = Self.mainWindowTitle
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = Self.mainWindowMinimumSize
        window.tabbingMode = .disallowed
    }

    /// Shows an existing window with the given title, or creates a new one.
    func showOrCreateWindow(
        title: String,
        size: NSSize,
        styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable],
        configure: ((NSWindow) -> Void)? = nil,
        onShow: ((NSWindow) -> Void)? = nil,
        rootView: () -> some View
    ) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        for window in NSApp.windows where window.title == title {
            window.makeKeyAndOrderFront(nil)
            if window.isMiniaturized { window.deminiaturize(nil) }
            onShow?(window)
            return
        }

        let window = NSWindow(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // Use a hosting *controller* (not a bare NSHostingView) so SwiftUI is
        // constrained to the window's content bounds and lays out correctly on
        // first show. A bare NSHostingView offers an unconstrained width on the
        // initial pass, which makes the flexible column overflow the window.
        window.contentViewController = NSHostingController(rootView: rootView())
        window.title = title
        configure?(window)
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        onShow?(window)
    }

    func showOrCreateMainWindow() {
        appDelegateLogger.info("showOrCreateMainWindow called")
        guard let repoVM = repoViewModel,
              let worktreeVM = worktreeViewModel else {
            appDelegateLogger.warning("showOrCreateMainWindow: view models not connected")
            return
        }

        guard let store = shortcutStore else {
            appDelegateLogger.warning("showOrCreateMainWindow: shortcutStore not connected")
            return
        }
        showOrCreateWindow(
            title: Self.mainWindowTitle,
            size: NSSize(width: 1180, height: 740),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            configure: { window in
                // The glass toolbar is the first row of the content and extends up
                // under this transparent titlebar; the native traffic lights overlay
                // its left clearance.
                Self.configureMainWindowChrome(window)
                window.delegate = self
                Self.centerTrafficLightsAfterLayout(in: window)
            }
        ) {
            ContentView(repoViewModel: repoVM, worktreeViewModel: worktreeVM)
                .environment(store)
                .frame(minWidth: 860, minHeight: 520)
        }
    }

    @objc func showOrCreateSettingsWindow() {
        guard let updaterManager else { return }
        guard let shortcutStore else { return }

        showOrCreateWindow(
            title: Self.settingsWindowTitle,
            size: NSSize(width: 500, height: 450),
            styleMask: [.titled, .closable]
        ) {
            SettingsView(updaterManager: updaterManager, store: shortcutStore)
        }
    }
}

// MARK: - Traffic-light centering

extension AppDelegate: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) { recenterTrafficLights(notification) }
    func windowDidUpdate(_ notification: Notification) { recenterTrafficLights(notification) }

    private func recenterTrafficLights(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.title == Self.mainWindowTitle else { return }
        Self.centerTrafficLights(in: window)
    }

    /// Moves the native traffic-light buttons to the vertical center of the 52pt
    /// glass toolbar (they otherwise sit at the standard titlebar position, ~12pt
    /// too high). Re-applied on every window update so the system can't reset it.
    static func centerTrafficLights(
        in window: NSWindow,
        toolbarHeight: CGFloat = 52,
        trafficLightLeadingInset: CGFloat = 17
    ) {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard let container = buttons.first?.superview,
              let contentView = window.contentView else { return }
        container.superview?.clipsToBounds = false
        container.clipsToBounds = false
        // Map the toolbar's vertical center from window coordinates into the
        // button container. NSHostingController content views do not convert
        // reliably across the titlebar hierarchy.
        let centerInContainer = container.convert(
            CGPoint(x: 0, y: contentView.bounds.height - toolbarHeight / 2), from: nil
        )
        let currentLeadingInset = buttons.map { $0.frame.origin.x }.min() ?? trafficLightLeadingInset
        let horizontalDelta = trafficLightLeadingInset - currentLeadingInset
        for button in buttons {
            let desiredX = button.frame.origin.x + horizontalDelta
            let desiredY = centerInContainer.y - button.frame.height / 2
            if abs(button.frame.origin.x - desiredX) > 0.5 || abs(button.frame.origin.y - desiredY) > 0.5 {
                button.setFrameOrigin(NSPoint(x: desiredX, y: desiredY))
            }
        }
    }

    static func centerTrafficLightsAfterLayout(in window: NSWindow) {
        centerTrafficLights(in: window)
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            centerTrafficLights(in: window)
        }
    }
}
