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
    }
}

/// Captures `@Environment(\.openWindow)` from the SwiftUI environment
/// and stores the action in AppDelegate so it can open a new window
/// even after the original window has been closed and deallocated.
private struct OpenWindowModifier: ViewModifier {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                appDelegate.openMainWindow = { [openWindow] in
                    openWindow(id: "main")
                }
            }
    }
}
