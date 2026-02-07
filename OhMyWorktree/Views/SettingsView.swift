import SwiftUI

struct SettingsView: View {
    @AppStorage("copyEnvFilesEnabled") private var copyEnvFilesEnabled = true

    var body: some View {
        Form {
            Section("Worktree Creation") {
                Toggle("Copy .env files to new worktrees", isOn: $copyEnvFilesEnabled)
                Text("When enabled, .env files from the repository root are automatically copied into newly created worktrees.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 150)
        .padding()
    }
}
