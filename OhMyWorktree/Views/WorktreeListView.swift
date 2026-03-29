import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var viewModel: WorktreeListViewModel
    @State private var selectedIDs: Set<UUID> = []
    @State private var renamingWorktreeID: UUID?
    @State private var forceRemoveTarget: ForceRemoveTarget?
    @State private var confirmBulkRemove = false
    @State private var confirmBulkQuickRemove = false
    @State private var quickRemoveTarget: Worktree?

    private enum ForceRemoveTarget {
        case single(Worktree)
        case selectedWorktrees(count: Int)
    }

    var body: some View {
        Group {
            if viewModel.repository == nil {
                emptyStateView(
                    icon: "folder.badge.questionmark",
                    title: "No Repository Selected",
                    subtitle: "Add a repository to get started"
                )
            } else if viewModel.isLoading && viewModel.worktrees.isEmpty {
                ProgressView("Loading worktrees...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.worktrees.isEmpty && !viewModel.jobQueue.hasActiveJobs {
                emptyStateView(
                    icon: "tray",
                    title: "No Worktrees",
                    subtitle: "Click + to create a new worktree"
                )
            } else {
                let jobStates = jobStateByWorktreeID
                List(selection: $selectedIDs) {
                    ForEach(viewModel.worktrees) { worktree in
                        worktreeRow(for: worktree, jobStates: jobStates)
                            .tag(worktree.id)
                            .contextMenu {
                                contextMenuItems(for: worktree)
                            }
                    }
                }
                .listStyle(.inset)
                .onChange(of: selectedIDs) { _, newIDs in
                    guard newIDs != viewModel.selectedWorktreeIDs else { return }
                    let vm = viewModel
                    Task { @MainActor in vm.selectedWorktreeIDs = newIDs }
                }
                .onChange(of: viewModel.selectedWorktreeIDs) { _, newIDs in
                    if newIDs != selectedIDs { selectedIDs = newIDs }
                }
                .onKeyPress(.return) {
                    guard renamingWorktreeID == nil,
                          selectedIDs.count == 1,
                          let id = selectedIDs.first,
                          let worktree = viewModel.worktrees.first(where: { $0.id == id })
                    else { return .ignored }
                    renamingWorktreeID = worktree.id
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard !selectedIDs.isEmpty else { return .ignored }
                    selectedIDs = []
                    return .handled
                }
            }
        }
        .confirmationDialog(
            forceRemoveConfirmationTitle,
            isPresented: Binding(
                get: { forceRemoveTarget != nil },
                set: { if !$0 { forceRemoveTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Force Remove", role: .destructive) {
                switch forceRemoveTarget {
                case .single(let worktree):
                    viewModel.removeWorktree(worktree, force: true)
                case .selectedWorktrees:
                    viewModel.removeSelectedWorktrees(force: true)
                case nil:
                    break
                }
                forceRemoveTarget = nil
            }
            Button("Cancel", role: .cancel) { forceRemoveTarget = nil }
        } message: {
            Text("Uncommitted changes will be lost. This cannot be undone.")
        }
        .confirmationDialog(
            "Remove \(viewModel.selectedWorktreeIDs.count) Worktrees?",
            isPresented: $confirmBulkRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                viewModel.removeSelectedWorktrees(force: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Worktrees with uncommitted changes will not be removed.")
        }
        .confirmationDialog(
            "Quick Remove \(viewModel.selectedWorktreeIDs.count) Worktrees?",
            isPresented: $confirmBulkQuickRemove,
            titleVisibility: .visible
        ) {
            Button("Quick Remove", role: .destructive) {
                viewModel.quickRemoveSelectedWorktrees()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Directories will be moved to Trash. Git worktree registration will be removed immediately.")
        }
        .confirmationDialog(
            "Quick Remove '\(quickRemoveTarget?.displayName ?? "")'?",
            isPresented: Binding(
                get: { quickRemoveTarget != nil },
                set: { if !$0 { quickRemoveTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Quick Remove", role: .destructive) {
                if let worktree = quickRemoveTarget {
                    viewModel.quickRemoveWorktree(worktree)
                }
                quickRemoveTarget = nil
            }
            Button("Cancel", role: .cancel) { quickRemoveTarget = nil }
        } message: {
            Text("The directory will be moved to Trash. Uncommitted changes will not be checked.")
        }
    }

    private var forceRemoveConfirmationTitle: String {
        switch forceRemoveTarget {
        case .single(let worktree):
            return "Force Remove '\(worktree.displayName)'?"
        case .selectedWorktrees(let count):
            return "Force Remove \(count) Worktree\(count == 1 ? "" : "s")?"
        case nil:
            return ""
        }
    }

    // MARK: - Worktree Row

    /// Pre-computed job state lookup to avoid O(N*M) per-row linear scans.
    private var jobStateByWorktreeID: [UUID: BackgroundJobState] {
        var result: [UUID: BackgroundJobState] = [:]
        for job in viewModel.jobQueue.jobs where job.state.isActive {
            result[job.worktreeID] = job.state
        }
        return result
    }

    /// Resolves the PR for a worktree, checking local branch then remote branch fallback.
    private func pullRequest(for worktree: Worktree) -> PullRequestInfo? {
        worktree.branch.flatMap { viewModel.pullRequests[$0] }
            ?? worktree.prRemoteBranch.flatMap { viewModel.pullRequests[$0] }
    }

    private func worktreeRow(for worktree: Worktree, jobStates: [UUID: BackgroundJobState]) -> some View {
        let jobState = jobStates[worktree.id]
        return WorktreeRowView(
            worktree: worktree,
            pullRequest: pullRequest(for: worktree),
            jobState: jobState,
            isRenaming: renamingWorktreeID == worktree.id,
            onOpenPullRequest: { viewModel.openPullRequest(for: worktree) },
            onRename: { newName in
                renamingWorktreeID = nil
                Task { await viewModel.renameWorktree(worktree, newName: newName) }
            },
            onCancelRename: { renamingWorktreeID = nil }
        )
        .help("Right-click for actions")
    }

    // MARK: - Empty State

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for worktree: Worktree) -> some View {
        let actions = viewModel.contextMenuActions(for: worktree)
        let isMultiSelected = viewModel.selectedWorktreeIDs.count >= 2
            && viewModel.selectedWorktreeIDs.contains(worktree.id)

        Button("Rename") { renamingWorktreeID = worktree.id }
            .disabled(!actions.canRename)

        Divider()

        Button("Open in iTerm") { Task { await viewModel.openInITerm(worktree) } }
            .disabled(!viewModel.isITermAvailable || !actions.canOpen)
        Button("Open in Ghostty") { Task { await viewModel.openInGhostty(worktree) } }
            .disabled(!viewModel.isGhosttyAvailable || !actions.canOpen)
        Button("Open in VSCode") { Task { await viewModel.openInVSCode(worktree) } }
            .disabled(!viewModel.isVSCodeAvailable || !actions.canOpen)
        Button("Open in Cursor") { Task { await viewModel.openInCursor(worktree) } }
            .disabled(!viewModel.isCursorAvailable || !actions.canOpen)
        Button("Open in cmux") { Task { await viewModel.openInCmux(worktree) } }
            .disabled(!viewModel.isCmuxAvailable || !actions.canOpen)

        if !isMultiSelected, let pr = pullRequest(for: worktree) {
            Divider()
            Button("Open Pull Request #\(pr.number)") { viewModel.openPullRequest(for: worktree) }
        }

        if !worktree.isBare {
            Divider()
            Button("Git Pull") { viewModel.gitPull(worktree) }
                .disabled(!actions.canGitPull)
        }

        Divider()

        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
        }
        .disabled(!actions.canShowInFinder)

        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worktree.path, forType: .string)
        }
        .disabled(!actions.canCopyPath)

        removalMenuItems(for: worktree, actions: actions, isMultiSelected: isMultiSelected)
    }

    @ViewBuilder
    private func removalMenuItems(for worktree: Worktree, actions: ContextMenuActions, isMultiSelected: Bool) -> some View {
        if isMultiSelected {
            if actions.canRemove {
                Divider()
                Button("Remove Selected Worktrees", role: .destructive) {
                    confirmBulkRemove = true
                }
                Button("Force Remove Selected Worktrees", role: .destructive) {
                    forceRemoveTarget = .selectedWorktrees(count: viewModel.selectedWorktreeIDs.count)
                }
                Button("Quick Remove Selected Worktrees") {
                    confirmBulkQuickRemove = true
                }
            }
        } else if let repository = viewModel.repository, !worktree.isRoot(of: repository) {
            Divider()
            Button("Remove Worktree", role: .destructive) {
                viewModel.removeWorktree(worktree)
            }
            .disabled(!actions.canRemove)

            Button("Force Remove Worktree", role: .destructive) {
                forceRemoveTarget = .single(worktree)
            }
            .disabled(!actions.canForceRemove)

            Button("Quick Remove Worktree") {
                quickRemoveTarget = worktree
            }
            .disabled(!actions.canQuickRemove)
        }
    }
}
