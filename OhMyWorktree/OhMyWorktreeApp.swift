import SwiftUI

@main
struct OhMyWorktreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var repoViewModel = RepositoryListViewModel()
    @State private var worktreeViewModel = WorktreeListViewModel()
    @State private var updaterManager = UpdaterManager()
    @State private var shortcutStore = ShortcutStore()

    var body: some Scene {
        // Connect view models to AppDelegate during Scene body evaluation,
        // so the menu bar works even if the main window hasn't appeared yet
        // (e.g. cold start after reboot with Login Items).
        // swiftlint:disable:next redundant_discardable_let
        let _ = connectAppDelegate()

        WindowGroup(id: "main") {
            ContentView(repoViewModel: repoViewModel, worktreeViewModel: worktreeViewModel)
                .environment(shortcutStore)
        }
        .defaultSize(width: 1180, height: 740)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
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
        if appDelegate.shortcutStore !== shortcutStore {
            appDelegate.shortcutStore = shortcutStore
            appDelegate.setupGlobalHotkey()
        }
    }
}
