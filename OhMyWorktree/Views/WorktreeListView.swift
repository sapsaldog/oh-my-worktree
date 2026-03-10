import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var viewModel: WorktreeListViewModel
    @State private var selectedIDs: Set<UUID> = []
    @State private var renamingWorktreeID: UUID?
    @State private var forceRemoveTarget: ForceRemoveTarget?

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
                List(selection: $selectedIDs) {
                    ForEach(viewModel.worktrees) { worktree in
                        worktreeRow(for: worktree)
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

    private func worktreeRow(for worktree: Worktree) -> some View {
        let jobState = viewModel.jobQueue.jobs.first { $0.worktreeID == worktree.id }?.state
        return WorktreeRowView(
            worktree: worktree,
            pullRequest: worktree.branch.flatMap { viewModel.pullRequests[$0] },
            jobState: jobState,
            isRenaming: renamingWorktreeID == worktree.id,
            onOpenPullRequest: { viewModel.openPullRequest(for: worktree) },
            onRename: { newName in
                renamingWorktreeID = nil
                Task { await viewModel.renameWorktree(worktree, newName: newName) }
            },
            onCancelRename: { renamingWorktreeID = nil }
        )
        // Fix 10: Tooltip improves discoverability for users who may not know
        // that context menu actions (open, rename, pull, remove) are on right-click.
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

        if !isMultiSelected, let branch = worktree.branch, let pr = viewModel.pullRequests[branch] {
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

        if isMultiSelected {
            if actions.canRemove {
                Divider()
                Button("Remove Selected Worktrees", role: .destructive) {
                    viewModel.removeSelectedWorktrees(force: false)
                }
                Button("Force Remove Selected Worktrees", role: .destructive) {
                    forceRemoveTarget = .selectedWorktrees(count: viewModel.selectedWorktreeIDs.count)
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
        }
    }
}
