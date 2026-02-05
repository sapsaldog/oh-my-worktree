import SwiftUI

@main
struct OhMyWorktreeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, minHeight: 300)
        }
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentSize)
    }
}
