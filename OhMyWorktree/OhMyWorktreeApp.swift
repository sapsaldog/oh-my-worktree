import SwiftUI

@main
struct OhMyWorktreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var repoViewModel = RepositoryListViewModel()
    @StateObject private var worktreeViewModel = WorktreeListViewModel()
    @StateObject private var updaterManager = UpdaterManager()
    @StateObject private var shortcutManager = ShortcutManager()

    init() {
        ShortcutManager.migrateLegacyKeys()
    }

    var body: some Scene {
        // Connect view models to AppDelegate during Scene body evaluation,
        // so the menu bar works even if the main window hasn't appeared yet
        // (e.g. cold start after reboot with Login Items).
        // swiftlint:disable:next redundant_discardable_let
        let _ = connectAppDelegate()

        WindowGroup(id: "main") {
            ContentView(repoViewModel: repoViewModel, worktreeViewModel: worktreeViewModel)
                .environmentObject(shortcutManager)
                .frame(minWidth: 400, minHeight: 300)
        }
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appDelegate.showOrCreateSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Navigate") {
                Button("Previous Repository") {
                    Task { await repoViewModel.selectPreviousRepository() }
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("Next Repository") {
                    Task { await repoViewModel.selectNextRepository() }
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Oh My Worktree Help") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/sapsaldog/oh-my-worktree/tree/main/docs#readme")!)
                }
                Button("Report Issue...") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/sapsaldog/oh-my-worktree/issues")!)
                }
            }
        }
    }

    private func connectAppDelegate() {
        appDelegate.repoViewModel = repoViewModel
        appDelegate.worktreeViewModel = worktreeViewModel
        appDelegate.updaterManager = updaterManager
        if appDelegate.shortcutManager !== shortcutManager {
            appDelegate.shortcutManager = shortcutManager
            appDelegate.observeShortcutChanges()
            appDelegate.setupGlobalHotkey()
        }
    }
}
