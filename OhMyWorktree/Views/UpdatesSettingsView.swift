import SwiftUI

struct UpdatesSettingsView: View {
    @ObservedObject var updaterManager: UpdaterManager

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updaterManager.automaticallyChecksForUpdates },
                    set: { updaterManager.automaticallyChecksForUpdates = $0 }
                ))
                Button("Check for Updates Now") {
                    updaterManager.checkForUpdates()
                }
                .disabled(!updaterManager.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
    }
}
