import SwiftUI

/// New Worktree sheet: a random-but-editable name (shuffle), base branch, and a
/// per-creation `.worktreeinclude` copy toggle.
struct CreateWorktreeSheet: View {
    @Bindable var worktreeViewModel: WorktreeListViewModel
    var repoName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.omwAccent) private var accent
    @AppStorage("copyEnvFilesEnabled") private var globalCopy = true

    @State private var name = ""
    @State private var baseBranch = ""
    @State private var copyFiles = true
    @State private var branches: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            form
            Divider()
            footer
        }
        .frame(width: 460)
        .tint(accent)
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("New Worktree").font(.system(size: 16, weight: .bold))
            Text("A fresh working tree in \(repoName). Pick a memorable name — it becomes the folder.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.init(top: 18, leading: 20, bottom: 0, trailing: 20))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Worktree name").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("e.g. tokyo-lunch", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button { name = randomName() } label: { Image(systemName: "shuffle") }
                        .help("Generate another")
                }
                Text("A new branch will be created and checked out.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Base branch").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Picker("", selection: $baseBranch) {
                    if branches.isEmpty { Text("main").tag("main") }
                    ForEach(branches, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Toggle(isOn: $copyFiles) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copy files to new worktree").font(.system(size: 13, weight: .medium))
                    Text("Apply .worktreeinclude patterns (.env*, local configs)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Create Worktree") {
                let chosen = name
                let base = baseBranch
                let copy = copyFiles
                Task { await worktreeViewModel.addWorktree(name: chosen, baseBranch: base, copyFiles: copy) }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.init(top: 12, leading: 20, bottom: 16, trailing: 20))
    }

    private func load() {
        if name.isEmpty { name = randomName() }
        copyFiles = globalCopy
        Task {
            let list = await worktreeViewModel.availableBranches()
            branches = list
            if baseBranch.isEmpty { baseBranch = list.first ?? "main" }
        }
    }

    private func randomName() -> String {
        RandomNameGenerator.generate(existingFolderNames: Set(worktreeViewModel.worktrees.map(\.folderName)))
    }
}
