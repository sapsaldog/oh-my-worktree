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
    @State private var showBranchPicker = false
    @State private var branchFilter = ""
    @FocusState private var branchFilterFocused: Bool

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
                baseBranchPicker
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copy files to new worktree").font(.system(size: 13, weight: .medium))
                    Text("Apply .worktreeinclude patterns (.env*, local configs)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                Toggle("Copy files to new worktree", isOn: $copyFiles).toggleStyle(.omwSwitch)
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

    // MARK: - Base branch selector

    /// The repo's default branch (main/master) — label & value of the first segment.
    private var defaultBranchName: String {
        WorktreeListViewModel.defaultBaseBranch(from: branches)
    }

    /// True when `baseBranch` was chosen via "More…" rather than a fixed segment.
    private var isCustomBaseBranch: Bool {
        !baseBranch.isEmpty && baseBranch != defaultBranchName && baseBranch != "HEAD"
    }

    // NOTE: the selected segment is filled with the accent color by product
    // decision — a deliberate deviation from the prototype's components.css, which
    // specs `.mac-seg` selections as neutral `--control-bg` (see Settings tabs).
    private var baseBranchPicker: some View {
        HStack(spacing: 2) {
            baseSegment(label: defaultBranchName, value: defaultBranchName)
            baseSegment(label: "Current HEAD", value: "HEAD")
            moreSegment
            Spacer(minLength: 0)
        }
        .padding(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OMWColor.fillTertiary, in: RoundedRectangle(cornerRadius: OMWRadius.md))
    }

    private func baseSegment(label: String, value: String) -> some View {
        let selected = baseBranch == value
        return Button { baseBranch = value } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : OMWColor.labelSecondary)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(selected ? AnyShapeStyle(accent) : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var moreSegment: some View {
        let selected = isCustomBaseBranch
        return Button {
            branchFilter = ""
            showBranchPicker = true
        } label: {
            HStack(spacing: 4) {
                Text(selected ? baseBranch : "More…")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: selected ? 180 : nil, alignment: .leading)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(selected ? Color.white : OMWColor.labelSecondary)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(selected ? AnyShapeStyle(accent) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showBranchPicker, arrowEdge: .bottom) { branchPickerPopover }
    }

    private var branchPickerPopover: some View {
        VStack(spacing: 0) {
            TextField("Filter branches…", text: $branchFilter)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($branchFilterFocused)
                .onSubmit { if let first = filteredBranches.first { select(first) } }
                .padding(8)
            Divider()
            branchList
        }
        .frame(width: 260)
        .onAppear { branchFilterFocused = true }
    }

    @ViewBuilder private var branchList: some View {
        let matches = filteredBranches
        if matches.isEmpty {
            Text(branches.isEmpty ? "No branches" : "No matching branches")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matches, id: \.self) { branch in
                        Button { select(branch) } label: { branchRow(branch) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func branchRow(_ branch: String) -> some View {
        HStack(spacing: 8) {
            Text(branch).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if baseBranch == branch {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var filteredBranches: [String] {
        WorktreeListViewModel.filterBranches(branches, matching: branchFilter)
    }

    private func select(_ branch: String) {
        baseBranch = branch
        showBranchPicker = false
        branchFilter = ""
    }

    private func load() {
        if name.isEmpty { name = randomName() }
        copyFiles = globalCopy
        Task {
            let list = await worktreeViewModel.availableBranches()
            branches = list
            if baseBranch.isEmpty { baseBranch = WorktreeListViewModel.defaultBaseBranch(from: list) }
        }
    }

    private func randomName() -> String {
        RandomNameGenerator.generate(existingFolderNames: Set(worktreeViewModel.worktrees.map(\.folderName)))
    }
}
