import SwiftUI

@main
struct OhMyWorktreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var repoViewModel = RepositoryListViewModel()
    @StateObject private var worktreeViewModel = WorktreeListViewModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(repoViewModel: repoViewModel, worktreeViewModel: worktreeViewModel)
                .frame(minWidth: 400, minHeight: 300)
                .modifier(OpenWindowModifier(appDelegate: appDelegate))
                .onAppear {
                    NSApp.setActivationPolicy(.accessory)
                    appDelegate.repoViewModel = repoViewModel
                    appDelegate.worktreeViewModel = worktreeViewModel
                }
        }
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}

/// Captures `@Environment(\.openWindow)` and `@Environment(\.openSettings)`
/// from the SwiftUI environment and stores the actions in AppDelegate
/// so they can be triggered from the menu bar even after the window is closed.
private struct OpenWindowModifier: ViewModifier {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .onAppear {
                appDelegate.openMainWindow = { [openWindow] in
                    openWindow(id: "main")
                }
                appDelegate.openSettings = { [openSettings] in
                    openSettings()
                }
            }
    }
}
