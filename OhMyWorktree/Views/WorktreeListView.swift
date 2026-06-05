import SwiftUI

struct WorktreeListView: View {
    var viewModel: WorktreeListViewModel
    @Environment(ShortcutStore.self) var shortcutStore
    @State private var selectedIDs: Set<UUID> = []
    @State private var renamingWorktreeID: UUID?
    @State private var forceRemoveTarget: ForceRemoveTarget?
    @State private var confirmRemoveTarget: Worktree?
    @State private var confirmBulkRemove = false
    @State private var confirmBulkQuickRemove = false
    @State private var quickRemoveTarget: Worktree?

    enum ForceRemoveTarget {
        case single(Worktree)
        case selectedWorktrees(count: Int)
    }

    var body: some View {
        listContent
            .modifier(RemovalDialogsModifier(
                viewModel: viewModel,
                confirmRemoveTarget: $confirmRemoveTarget,
                forceRemoveTarget: $forceRemoveTarget,
                confirmBulkRemove: $confirmBulkRemove,
                confirmBulkQuickRemove: $confirmBulkQuickRemove,
                quickRemoveTarget: $quickRemoveTarget
            ))
    }

    @ViewBuilder
    private var listContent: some View {
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
            worktreeList
        }
    }

    // MARK: - Worktree List

    private var worktreeList: some View {
        let jobStates = jobStateByWorktreeID
        return List(selection: $selectedIDs) {
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
            viewModel.selectedWorktreeIDs = newIDs
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
        .onChange(of: viewModel.pendingDelete) { _, pending in
            guard let pending else { return }
            viewModel.pendingDelete = nil
            switch pending {
            case .remove: triggerRemove()
            case .forceRemove: triggerForceRemove()
            case .quickRemove: triggerQuickRemove()
            }
        }
        .background(TableViewFocuser(worktreeCount: viewModel.worktrees.count))
    }

    private func triggerRemove() {
        if selectedIDs.count >= 2 {
            confirmBulkRemove = true
        } else if let id = selectedIDs.first,
                  let wt = viewModel.worktrees.first(where: { $0.id == id }) {
            confirmRemoveTarget = wt
        }
    }

    private func triggerForceRemove() {
        if selectedIDs.count >= 2 {
            forceRemoveTarget = .selectedWorktrees(count: selectedIDs.count)
        } else if let id = selectedIDs.first,
                  let wt = viewModel.worktrees.first(where: { $0.id == id }) {
            forceRemoveTarget = .single(wt)
        }
    }

    private func triggerQuickRemove() {
        if selectedIDs.count >= 2 {
            confirmBulkQuickRemove = true
        } else if let id = selectedIDs.first,
                  let wt = viewModel.worktrees.first(where: { $0.id == id }) {
            quickRemoveTarget = wt
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
            .keyboardShortcut(.return, modifiers: [])

        Divider()

        contextMenuButton("Open in iTerm", action: .openITerm) { Task { await viewModel.openInITerm(worktree) } }
            .disabled(!viewModel.isITermAvailable || !actions.canOpen)
        contextMenuButton("Open in Ghostty", action: .openGhostty) { Task { await viewModel.openInGhostty(worktree) } }
            .disabled(!viewModel.isGhosttyAvailable || !actions.canOpen)
        contextMenuButton("Open in VSCode", action: .openVSCode) { Task { await viewModel.openInVSCode(worktree) } }
            .disabled(!viewModel.isVSCodeAvailable || !actions.canOpen)
        contextMenuButton("Open in Cursor", action: .openCursor) { Task { await viewModel.openInCursor(worktree) } }
            .disabled(!viewModel.isCursorAvailable || !actions.canOpen)
        contextMenuButton("Open in cmux", action: .openCmux) { Task { await viewModel.openInCmux(worktree) } }
            .disabled(!viewModel.isCmuxAvailable || !actions.canOpen)

        if !isMultiSelected, let pr = pullRequest(for: worktree) {
            Divider()
            Button("Open Pull Request #\(pr.number)") { viewModel.openPullRequest(for: worktree) }
        }

        if !worktree.isBare {
            Divider()
            contextMenuButton("Git Pull", action: .gitPull) { viewModel.gitPull(worktree) }
                .disabled(!actions.canGitPull)
        }

        Divider()

        contextMenuButton("Show in Finder", action: .showInFinder) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
        }
        .disabled(!actions.canShowInFinder)

        contextMenuButton("Copy Path", action: .copyPath) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worktree.path, forType: .string)
        }
        .disabled(!actions.canCopyPath)

        removalMenuItems(for: worktree, actions: actions, isMultiSelected: isMultiSelected)
    }

    @ViewBuilder
    private func contextMenuButton(
        _ title: String,
        action: ShortcutAction,
        role: ButtonRole? = nil,
        perform: @escaping () -> Void
    ) -> some View {
        Button(title, role: role, action: perform)
            .keyboardShortcut(shortcutStore.swiftUIShortcut(for: action))
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
                Button("Quick Remove Selected Worktrees", role: .destructive) {
                    confirmBulkQuickRemove = true
                }
            }
        } else if let repository = viewModel.repository, !worktree.isRoot(of: repository) {
            Divider()
            contextMenuButton("Remove Worktree", action: .removeWorktree, role: .destructive) {
                triggerRemove()
            }
            .disabled(!actions.canRemove)

            contextMenuButton("Force Remove Worktree", action: .forceRemoveWorktree, role: .destructive) {
                triggerForceRemove()
            }
            .disabled(!actions.canForceRemove)

            contextMenuButton("Quick Remove Worktree", action: .quickRemoveWorktree, role: .destructive) {
                triggerQuickRemove()
            }
            .disabled(!actions.canQuickRemove)
        }
    }

}
