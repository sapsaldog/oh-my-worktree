import SwiftUI

@main
struct OhMyWorktreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var repoViewModel = RepositoryListViewModel()
    @StateObject private var worktreeViewModel = WorktreeListViewModel()
    @StateObject private var updaterManager = UpdaterManager()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(repoViewModel: repoViewModel, worktreeViewModel: worktreeViewModel)
                .frame(minWidth: 400, minHeight: 300)
                .sheet(isPresented: $worktreeViewModel.isShowingImportPR) {
                    ImportPRView(worktreeViewModel: worktreeViewModel)
                }
                .modifier(OpenWindowModifier(appDelegate: appDelegate, worktreeViewModel: worktreeViewModel))
                .onAppear {
                    appDelegate.repoViewModel = repoViewModel
                    appDelegate.worktreeViewModel = worktreeViewModel
                    appDelegate.updaterManager = updaterManager
                }
        }
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(updaterManager: updaterManager)
        }
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
        content
            .onAppear {
                appDelegate.openMainWindow = { [openWindow] in
                    openWindow(id: "main")
                }
                appDelegate.openImportPRWindow = { [openWindow, worktreeViewModel] in
                    openWindow(id: "main")
                    // Dispatch to the next run-loop tick so SwiftUI finishes setting
                    // up the window's view hierarchy (including the .sheet modifier)
                    // before we present the sheet.
                    DispatchQueue.main.async {
                        worktreeViewModel.isShowingImportPR = true
                    }
                }
                appDelegate.openSettings = { [openSettings] in
                    openSettings()
                }
            }
    }
}
