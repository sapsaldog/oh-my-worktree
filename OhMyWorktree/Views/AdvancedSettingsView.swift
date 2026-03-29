import SwiftUI

struct AdvancedSettingsView: View {
    @AppStorage(BackgroundTaskQueue.jobTimeoutSecondsKey)
    private var jobTimeoutSeconds = Int(BackgroundTaskQueue.defaultJobTimeoutSeconds)

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
    }

    private func clampTimeout(_ value: Int) -> Int {
        min(max(value, 30), 600)
    }
}
