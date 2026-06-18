import os
import ServiceManagement
import SwiftUI

private let logger = Logger(subsystem: "com.ohmyworktree", category: "Settings")

struct GeneralSettingsView: View {
    @AppStorage("copyEnvFilesEnabled") private var copyEnvFilesEnabled = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var installedDiffTools: [DiffTool] = []

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            let action = newValue ? "enable" : "disable"
                            logger.error(
                                "Failed to \(action) launch at login: \(error.localizedDescription)"
                            )
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text("Automatically start Oh My Worktree when you log in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Worktree Creation") {
                Toggle("Copy files to new worktrees", isOn: $copyEnvFilesEnabled)
                Text(
                    "When enabled, files matching .worktreeinclude patterns " +
                    "(or .env files by default) are automatically copied into newly created worktrees."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diff Tool") {
                LabeledContent("Open copied-file diffs in") {
                    DiffToolMenu(available: installedDiffTools)
                }
                Text("Clicking a copied file opens its diff in this tool. Only installed tools can be selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            installedDiffTools = DiffToolLauncher().installedTools()
        }
    }
}
