import SwiftUI

struct RepositorySettingsView: View {
    let repository: Repository
    let store: RepositoryStore

    @AppStorage("copyEnvFilesEnabled") private var globalDefault = true
    @State private var overrideValue: Bool?
    @State private var isLoaded = false

    private var effectiveValue: Bool {
        overrideValue ?? globalDefault
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(repository.name)
                .font(.headline)

            Divider()

            Toggle("Copy files on worktree creation", isOn: Binding(
                get: { effectiveValue },
                set: { newValue in
                    overrideValue = newValue
                    Task {
                        await store.setEnvCopyOverride(repositoryID: repository.id, enabled: newValue)
                    }
                }
            ))

            if overrideValue != nil {
                HStack {
                    Text("Overriding global default (\(globalDefault ? "on" : "off"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        overrideValue = nil
                        Task {
                            await store.removeEnvCopyOverride(repositoryID: repository.id)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .task {
            guard !isLoaded else { return }
            overrideValue = await store.getEnvCopyOverride(for: repository.id)
            isLoaded = true
        }
    }
}
