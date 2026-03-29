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
}

// MARK: - Main Menu (all in-app keyboard shortcuts via NSMenuItem)

extension AppDelegate {

    /// Sets up NSApp.mainMenu after macOS finishes its own menu bar setup.
    /// Must run via DispatchQueue.main.async to avoid being overwritten by
    /// macOS during .accessory → .regular activation policy transitions.
    func setupMainMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let mainMenu = NSMenu()

            let appMenuItem = NSMenuItem()
            let appMenu = NSMenu(title: "OhMyWorktree")
            let settingsItem = NSMenuItem(
                title: "Settings...",
                action: #selector(self.settingsClicked(_:)),
                keyEquivalent: ","
            )
            settingsItem.target = self
            appMenu.addItem(settingsItem)
            appMenu.addItem(.separator())
            let quitItem = NSMenuItem(
                title: "Quit Oh My Worktree",
                action: #selector(self.quitClicked(_:)),
                keyEquivalent: "q"
            )
            quitItem.target = self
            appMenu.addItem(quitItem)
            appMenuItem.submenu = appMenu
            mainMenu.addItem(appMenuItem)

            NSApp.mainMenu = mainMenu
        }
    }
}
