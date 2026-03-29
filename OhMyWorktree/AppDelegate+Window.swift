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

    /// Inserts a "Settings..." (Cmd+,) item into the existing application menu.
    /// macOS auto-creates the app menu when switching to .regular policy,
    /// and overwrites any NSApp.mainMenu we set. So we inject into its menu instead.
    func setupMainMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self,
                  let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu else { return }

            // Already injected
            guard !appMenu.items.contains(where: { $0.keyEquivalent == "," }) else { return }

            // Insert "Settings..." after "About" (index 1)
            let separator = NSMenuItem.separator()
            let settingsItem = NSMenuItem(
                title: "Settings...",
                action: #selector(self.settingsClicked(_:)),
                keyEquivalent: ","
            )
            settingsItem.target = self
            let insertIndex = min(1, appMenu.numberOfItems)
            appMenu.insertItem(separator, at: insertIndex)
            appMenu.insertItem(settingsItem, at: insertIndex)
        }
    }
}
