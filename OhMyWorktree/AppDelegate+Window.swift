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
                // Re-center the traffic lights as the window resizes.
                window.delegate = self
            },
            onShow: { window in
                // Center the native traffic lights in the 52pt glass toolbar now,
                // and again next tick to win against the titlebar's own layout pass.
                Self.centerTrafficLights(in: window, toolbarHeight: 52)
                Task { @MainActor in Self.centerTrafficLights(in: window, toolbarHeight: 52) }
            }
        ) {
            ContentView(repoViewModel: repoVM, worktreeViewModel: worktreeVM)
                .environment(store)
                .frame(minWidth: 860, minHeight: 520)
        }
    }

    /// Vertically centers the native traffic-light buttons within the custom
    /// `toolbarHeight`-tall glass toolbar (they otherwise sit near the very top,
    /// misaligned with the toolbar controls) by positioning their frames directly.
    static func centerTrafficLights(in window: NSWindow, toolbarHeight: CGFloat) {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard let container = buttons.first?.superview else { return }
        container.clipsToBounds = false
        container.layoutSubtreeIfNeeded()
        let markerID = "omwTrafficLight"
        let buttonViews = Set(buttons.map { $0 as NSView })
        let originalX = Dictionary(uniqueKeysWithValues: buttons.map { ($0, $0.frame.minX) })
        // Drop our previous pins *and* the system's own placement of these buttons,
        // so the titlebar can't snap them back to the top on the next layout pass.
        func involvesButton(_ constraint: NSLayoutConstraint) -> Bool {
            if constraint.identifier == markerID { return true }
            if let view = constraint.firstItem as? NSView, buttonViews.contains(view) { return true }
            if let view = constraint.secondItem as? NSView, buttonViews.contains(view) { return true }
            return false
        }
        NSLayoutConstraint.deactivate(container.constraints.filter(involvesButton))
        for button in buttons {
            button.translatesAutoresizingMaskIntoConstraints = false
            let leading = button.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                                          constant: originalX[button] ?? 0)
            let centerY = button.centerYAnchor.constraint(equalTo: container.topAnchor,
                                                          constant: toolbarHeight / 2)
            leading.identifier = markerID
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

extension AppDelegate: NSWindowDelegate {
    /// Re-center the traffic lights after the system re-lays them out on resize.
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.title == Self.mainWindowTitle else { return }
        Self.centerTrafficLights(in: window, toolbarHeight: 52)
    }
}
