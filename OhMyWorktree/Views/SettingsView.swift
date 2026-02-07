import os
import ServiceManagement
import SwiftUI

private let logger = Logger(subsystem: "com.ohmyworktree", category: "Settings")

struct SettingsView: View {
    @AppStorage("copyEnvFilesEnabled") private var copyEnvFilesEnabled = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
                            logger.error("Failed to \(newValue ? "enable" : "disable") launch at login: \(error.localizedDescription)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text("Automatically start Oh My Worktree when you log in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Worktree Creation") {
                Toggle("Copy .env files to new worktrees", isOn: $copyEnvFilesEnabled)
                Text("When enabled, .env files from the repository root are automatically copied into newly created worktrees.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .frame(width: 400, height: 300)
        .padding()
    }
}
