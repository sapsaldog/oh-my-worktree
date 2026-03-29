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

    func showOrCreateSettingsWindow() {
        guard let updaterManager else { return }
        guard let shortcutManager else { return }

        showOrCreateWindow(
            title: Self.settingsWindowTitle,
            size: NSSize(width: 500, height: 450),
            styleMask: [.titled, .closable]
        ) {
            SettingsView(updaterManager: updaterManager, shortcutManager: shortcutManager)
        }
    }

    // MARK: - Main Menu (keyboard shortcuts in windowed mode)

    func setupMainMenu() {
        guard NSApp.mainMenu == nil || NSApp.mainMenu?.item(withTitle: "OhMyWorktree") == nil else {
            return
        }

        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "OhMyWorktree")
        appMenu.addItem(
            withTitle: "Settings...",
            action: #selector(settingsClicked(_:)),
            keyEquivalent: ","
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Oh My Worktree",
            action: #selector(quitClicked(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }
}
