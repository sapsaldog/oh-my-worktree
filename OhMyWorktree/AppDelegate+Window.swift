import AppKit
import SwiftUI

// MARK: - Window Management

extension AppDelegate {

    /// Shows an existing window with the given title, or creates a new one.
    func showOrCreateWindow(
        title: String,
        size: NSSize,
        styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable],
        rootView: () -> some View
    ) {
        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows where window.title == title {
            window.makeKeyAndOrderFront(nil)
            if window.isMiniaturized { window.deminiaturize(nil) }
            return
        }

        let window = NSWindow(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: rootView())
        window.title = title
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func showOrCreateMainWindow() {
        guard let repoVM = repoViewModel,
              let worktreeVM = worktreeViewModel else {
            return
        }

        let sm = shortcutManager ?? ShortcutManager()
        setupMainMenu()
        showOrCreateWindow(
            title: Self.mainWindowTitle,
            size: NSSize(width: 500, height: 400)
        ) {
            ContentView(repoViewModel: repoVM, worktreeViewModel: worktreeVM)
                .environmentObject(sm)
                .frame(minWidth: 400, minHeight: 300)
        }
    }

    @objc func showOrCreateSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Main Menu (all in-app keyboard shortcuts via NSMenuItem)

extension AppDelegate {

    func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (Settings, Quit)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "OhMyWorktree")
        addMenuItem(to: appMenu, action: .openSettings, selector: #selector(settingsClicked(_:)))
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Oh My Worktree",
            action: #selector(quitClicked(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu (Add Repository, New Worktree)
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        addMenuItem(to: fileMenu, action: .addRepository, selector: #selector(addRepositoryShortcut(_:)))
        addMenuItem(to: fileMenu, action: .addWorktree, selector: #selector(newWorktreeClicked(_:)))
        fileMenu.addItem(.separator())
        addMenuItem(to: fileMenu, action: .removeWorktree, selector: #selector(removeWorktreeShortcut(_:)))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // View menu (Refresh)
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        addMenuItem(to: viewMenu, action: .refreshWorktrees, selector: #selector(refreshWorktreesShortcut(_:)))
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Open In menu (external tools)
        let openInMenuItem = NSMenuItem()
        let openInMenu = NSMenu(title: "Open In")
        addMenuItem(to: openInMenu, action: .openITerm, selector: #selector(openInITermShortcut(_:)))
        addMenuItem(to: openInMenu, action: .openGhostty, selector: #selector(openInGhosttyShortcut(_:)))
        addMenuItem(to: openInMenu, action: .openVSCode, selector: #selector(openInVSCodeShortcut(_:)))
        addMenuItem(to: openInMenu, action: .openCursor, selector: #selector(openInCursorShortcut(_:)))
        addMenuItem(to: openInMenu, action: .openCmux, selector: #selector(openInCmuxShortcut(_:)))
        openInMenuItem.submenu = openInMenu
        mainMenu.addItem(openInMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func addMenuItem(to menu: NSMenu, action: ShortcutAction, selector: Selector) {
        let sm = shortcutManager ?? ShortcutManager()
        let item = NSMenuItem(title: action.displayName, action: selector, keyEquivalent: "")
        item.target = self
        if let equiv = sm.menuItemKeyEquivalent(for: action) {
            item.keyEquivalent = equiv.key
            item.keyEquivalentModifierMask = equiv.modifiers
        }
        menu.addItem(item)
    }
}
