import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var viewModel: WorktreeListViewModel
    @State private var renamingWorktreeID: UUID?

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
                List(selection: $viewModel.selectedWorktreeIDs) {
                    ForEach(viewModel.worktrees) { worktree in
                        worktreeRow(for: worktree)
                            .tag(worktree.id)
                            .contextMenu {
                                contextMenuItems(for: worktree)
                            }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .onKeyPress(.return) {
                    guard renamingWorktreeID == nil,
                          viewModel.selectedWorktreeIDs.count == 1,
                          let id = viewModel.selectedWorktreeIDs.first,
                          let worktree = viewModel.worktrees.first(where: { $0.id == id })
                    else { return .ignored }
                    renamingWorktreeID = worktree.id
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard !viewModel.selectedWorktreeIDs.isEmpty else { return .ignored }
                    viewModel.selectedWorktreeIDs = []
                    return .handled
                }
                .onChange(of: viewModel.selectedWorktreeIDs) { _, ids in
                    if ids.count == 1, let id = ids.first {
                        viewModel.selectedWorktree = viewModel.worktrees.first { $0.id == id }
                    } else {
                        viewModel.selectedWorktree = nil
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.repository != nil {
                addWorktreeButton
                    .padding(12)
            }
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

    // MARK: - Add Button

    private var addWorktreeButton: some View {
        Button(action: {
            Task { await viewModel.addWorktree() }
        }) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .help("New Worktree")
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

        if let repository = viewModel.repository, !worktree.isRoot(of: repository) {
            Divider()
            if isMultiSelected {
                Button("Remove Selected Worktrees", role: .destructive) {
                    viewModel.removeSelectedWorktrees(force: false)
                }
                .disabled(!actions.canRemove)

                Button("Force Remove Selected Worktrees", role: .destructive) {
                    viewModel.removeSelectedWorktrees(force: true)
                }
                .disabled(!actions.canForceRemove)
            } else {
                Button("Remove Worktree", role: .destructive) {
                    viewModel.removeWorktree(worktree)
                }
                .disabled(!actions.canRemove)

                Button("Force Remove Worktree", role: .destructive) {
                    viewModel.removeWorktree(worktree, force: true)
                }
                .disabled(!actions.canForceRemove)
            }
        }
    }
}
