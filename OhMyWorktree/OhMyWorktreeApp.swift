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
                .sheet(isPresented: $worktreeViewModel.isShowingImportPR) {
                    ImportPRView(worktreeViewModel: worktreeViewModel)
                }
                .modifier(OpenWindowModifier(appDelegate: appDelegate, worktreeViewModel: worktreeViewModel))
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

/// Captures `@Environment(\.openWindow)` and `@Environment(\.openSettings)`
/// from the SwiftUI environment and stores the actions in AppDelegate
/// so they can be triggered from the menu bar even after the window is closed.
private struct OpenWindowModifier: ViewModifier {
    let appDelegate: AppDelegate
    let worktreeViewModel: WorktreeListViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        // Capture environment closures during body evaluation (not .onAppear)
        // so they're available even before the window appears on screen
        // (e.g. cold start via Login Items after reboot).
        // swiftlint:disable:next redundant_discardable_let
        let _ = captureEnvironment()
        content
    }

    private func captureEnvironment() {
        appDelegate.openMainWindow = { [openWindow] in
            openWindow(id: "main")
        }
        appDelegate.openImportPRWindow = { [openWindow, worktreeViewModel] in
            openWindow(id: "main")
            DispatchQueue.main.async {
                worktreeViewModel.isShowingImportPR = true
            }
        }
        appDelegate.openSettings = { [openSettings] in
            openSettings()
        }
    }
}
