import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var viewModel: WorktreeListViewModel

    var body: some View {
        Group {
            if viewModel.repository == nil {
                emptyStateView(
                    icon: "folder.badge.questionmark",
                    title: "No Repository Selected",
                    subtitle: "Add a repository to get started"
                )
            } else if viewModel.isLoading {
                ProgressView("Loading worktrees...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.worktrees.isEmpty {
                emptyStateView(
                    icon: "tray",
                    title: "No Worktrees",
                    subtitle: "Click + to create a new worktree"
                )
            } else {
                List(selection: Binding<Worktree.ID?>(
                    get: { viewModel.selectedWorktree?.id },
                    set: { newID in
                        Task { @MainActor in
                            viewModel.selectedWorktree = viewModel.worktrees.first { $0.id == newID }
                        }
                    }
                )) {
                    ForEach(viewModel.worktrees) { worktree in
                        WorktreeRowView(
                            worktree: worktree,
                            pullRequest: worktree.branch.flatMap { viewModel.pullRequests[$0] }
                        )
                            .tag(worktree.id)
                            .contextMenu {
                                contextMenuItems(for: worktree)
                            }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.repository != nil {
                addWorktreeButton
                    .padding(12)
            }
        }
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
            Task {
                await viewModel.addWorktree()
            }
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
        Button("Open in iTerm") {
            Task { await viewModel.openInITerm(worktree) }
        }
        .disabled(!viewModel.isITermAvailable)

        Button("Open in Ghostty") {
            Task { await viewModel.openInGhostty(worktree) }
        }
        .disabled(!viewModel.isGhosttyAvailable)

        Button("Open in VSCode") {
            Task { await viewModel.openInVSCode(worktree) }
        }
        .disabled(!viewModel.isVSCodeAvailable)

        Button("Open in Cursor") {
            Task { await viewModel.openInCursor(worktree) }
        }
        .disabled(!viewModel.isCursorAvailable)

        Button("Open in cmux") {
            Task { await viewModel.openInCmux(worktree) }
        }
        .disabled(!viewModel.isCmuxAvailable)

        if let branch = worktree.branch, let pr = viewModel.pullRequests[branch] {
            Divider()

            Button("Open Pull Request #\(pr.number)") {
                viewModel.openPullRequest(for: worktree)
            }
        }

        if let repository = viewModel.repository, worktree.isRoot(of: repository) {
            Divider()

            Button("Git Pull") {
                Task { await viewModel.gitPull(worktree) }
            }
        }

        Divider()

        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
        }

        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worktree.path, forType: .string)
        }

        if let repository = viewModel.repository, !worktree.isRoot(of: repository) {
            Divider()

            Button("Remove Worktree", role: .destructive) {
                Task { await viewModel.removeWorktree(worktree) }
            }
            .disabled(worktree.isBare)

            Button("Force Remove Worktree", role: .destructive) {
                Task { await viewModel.removeWorktree(worktree, force: true) }
            }
            .disabled(worktree.isBare)
        }
    }
}
