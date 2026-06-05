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
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            configure: { window in
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
                window.minSize = NSSize(width: 860, height: 520)
                window.tabbingMode = .disallowed
                // A native unified toolbar hosts the controls and lets macOS
                // vertically center the traffic lights for us.
                let delegate = MainToolbarDelegate(worktreeVM: worktreeVM)
                self.mainToolbarDelegate = delegate
                let toolbar = NSToolbar(identifier: "OMWMainToolbar")
                toolbar.delegate = delegate
                toolbar.showsBaselineSeparator = false
                window.toolbar = toolbar
                window.toolbarStyle = .unified
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

// MARK: - Main window toolbar

/// Hosts the toolbar controls in a native unified `NSToolbar`. A flexible space
/// keeps them right-aligned; the unified style lets macOS vertically center the
/// traffic lights, which can't be done reliably from outside the window.
@MainActor
final class MainToolbarDelegate: NSObject, NSToolbarDelegate {
    private let worktreeVM: WorktreeListViewModel
    private static let controls = NSToolbarItem.Identifier("OMWControls")

    init(worktreeVM: WorktreeListViewModel) {
        self.worktreeVM = worktreeVM
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.controls else { return nil }
        let hosting = NSHostingView(rootView: ToolbarControls(worktreeVM: worktreeVM))
        // Pin an explicit size: intrinsic sizing collapses the hosting view to
        // nothing, while no sizing lets the toolbar over-expand it. Width =
        // 14 padding + 230 search + 4×(10 gap + 30 button) + 14 padding = 418.
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.widthAnchor.constraint(equalToConstant: 418),
            hosting.heightAnchor.constraint(equalToConstant: 52)
        ])
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = hosting
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.controls]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.controls]
    }
}
