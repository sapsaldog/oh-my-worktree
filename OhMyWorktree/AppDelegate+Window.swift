import AppKit
import SwiftUI

// MARK: - Window Management

extension AppDelegate {

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
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
                window.minSize = NSSize(width: 860, height: 520)
                // No native tab bar (its "+" would intrude on the toolbar row).
                window.tabbingMode = .disallowed
            },
            onShow: { window in
                // Vertically center the traffic lights in the 52pt glass toolbar.
                Self.centerTrafficLights(in: window, toolbarHeight: 52)
            }
        ) {
            ContentView(repoViewModel: repoVM, worktreeViewModel: worktreeVM)
                .environment(store)
                .frame(minWidth: 860, minHeight: 520)
        }
    }

    /// Vertically centers the native traffic-light buttons within the custom
    /// `toolbarHeight`-tall glass toolbar (they otherwise sit near the very top,
    /// misaligned with the toolbar controls). Uses Auto Layout so the position
    /// survives live resize, and applies its constraints only once.
    static func centerTrafficLights(in window: NSWindow, toolbarHeight: CGFloat) {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard buttons.count == 3, let container = buttons.first?.superview else { return }
        let markerID = "omwTrafficLightCenter"
        // Apply our constraints only once (the window may be reused).
        guard !container.constraints.contains(where: { $0.identifier == markerID }) else { return }
        container.clipsToBounds = false
        container.layoutSubtreeIfNeeded()
        // Shift the buttons down from the titlebar center to the toolbar center.
        let offset = (toolbarHeight - container.bounds.height) / 2
        guard offset > 0 else { return }
        let originalXs = buttons.map(\.frame.minX)
        for (button, originalX) in zip(buttons, originalXs) {
            button.translatesAutoresizingMaskIntoConstraints = false
            let leading = button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: originalX)
            let centerY = button.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: offset)
            centerY.identifier = markerID
            NSLayoutConstraint.activate([leading, centerY])
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
