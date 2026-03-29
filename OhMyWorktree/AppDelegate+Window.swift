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

    /// Patches the existing application menu that macOS creates automatically.
    /// Instead of replacing NSApp.mainMenu (which macOS overrides on policy
    /// transitions), we find the Settings/Preferences item and rewire its action.
    func setupMainMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu else { return }

            // Find existing Cmd+, item (macOS creates "Settings..." or "Preferences...")
            if let existing = appMenu.items.first(where: { $0.keyEquivalent == "," }) {
                existing.action = #selector(self.settingsClicked(_:))
                existing.target = self
            } else {
                // No Settings item found — add one
                let item = NSMenuItem(
                    title: "Settings...",
                    action: #selector(self.settingsClicked(_:)),
                    keyEquivalent: ","
                )
                item.target = self
                appMenu.insertItem(item, at: min(1, appMenu.numberOfItems))
            }
        }
    }
}
