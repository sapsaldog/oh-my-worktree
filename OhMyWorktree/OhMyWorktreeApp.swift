import SwiftUI

@main
struct OhMyWorktreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var repoViewModel = RepositoryListViewModel()
    @StateObject private var worktreeViewModel = WorktreeListViewModel()
    @StateObject private var updaterManager = UpdaterManager()

    var body: some Scene {
        // Connect view models to AppDelegate during Scene body evaluation,
        // so the menu bar works even if the main window hasn't appeared yet
        // (e.g. cold start after reboot with Login Items).
        // swiftlint:disable:next redundant_discardable_let
        let _ = connectAppDelegate()

        WindowGroup(id: "main") {
            ContentView(repoViewModel: repoViewModel, worktreeViewModel: worktreeViewModel)
                .frame(minWidth: 400, minHeight: 300)
        }
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(updaterManager: updaterManager)
        }
    }

    private func connectAppDelegate() {
        appDelegate.repoViewModel = repoViewModel
        appDelegate.worktreeViewModel = worktreeViewModel
        appDelegate.updaterManager = updaterManager
    }
}
