import os
import ServiceManagement
import SwiftUI

private let logger = Logger(subsystem: "com.ohmyworktree", category: "Settings")

struct SettingsView: View {
    @ObservedObject var updaterManager: UpdaterManager
    @AppStorage("copyEnvFilesEnabled") private var copyEnvFilesEnabled = true
    @AppStorage(BackgroundTaskQueue.jobTimeoutSecondsKey)
    private var jobTimeoutSeconds = Int(BackgroundTaskQueue.defaultJobTimeoutSeconds)
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var commitHash: String {
        Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? "unknown"
    }

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
                            logger.error("Failed to \(action) launch at login: \(error.localizedDescription)")
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

            Section("Advanced") {
                LabeledContent("Background task timeout") {
                    HStack(spacing: 4) {
                        TextField("", value: $jobTimeoutSeconds, format: .number)
                            .frame(width: 50)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { jobTimeoutSeconds = clampTimeout(jobTimeoutSeconds) }
                            .onChange(of: jobTimeoutSeconds) { _, val in
                                jobTimeoutSeconds = clampTimeout(val)
                            }
                        Text("sec")
                            .foregroundStyle(.secondary)
                    }
                }
                Text(
                    "Maximum time allowed for Remove / Force Remove operations (30–600s). " +
                    "Quick Remove Worktree is not affected by this setting."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            Section {
                Text("v\(appVersion) (\(buildNumber)) · \(commitHash)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .padding()
    }

    private func clampTimeout(_ value: Int) -> Int {
        min(max(value, 30), 600)
    }
}
