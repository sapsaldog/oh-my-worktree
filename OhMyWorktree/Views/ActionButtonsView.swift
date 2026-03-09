import SwiftUI

struct ActionButtonsView: View {
    @ObservedObject var viewModel: WorktreeListViewModel
    @Environment(\.openWindow) private var openWindow

    private var hasSelection: Bool {
        viewModel.selectedWorktree != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            actionButton(
                title: "iTerm",
                icon: "terminal",
                isAvailable: viewModel.isITermAvailable
            ) {
                Task { await viewModel.openInITerm() }
            }

            actionButton(
                title: "Ghostty",
                icon: "terminal.fill",
                isAvailable: viewModel.isGhosttyAvailable
            ) {
                Task { await viewModel.openInGhostty() }
            }

            actionButton(
                title: "VSCode",
                icon: "chevron.left.forwardslash.chevron.right",
                isAvailable: viewModel.isVSCodeAvailable
            ) {
                Task { await viewModel.openInVSCode() }
            }

            actionButton(
                title: "Cursor",
                icon: "cursorarrow.rays",
                isAvailable: viewModel.isCursorAvailable
            ) {
                Task { await viewModel.openInCursor() }
            }

            actionButton(
                title: "cmux",
                icon: "rectangle.topthird.inset.filled",
                isAvailable: viewModel.isCmuxAvailable
            ) {
                Task { await viewModel.openInCmux() }
            }

            Spacer()

            newWorktreeButton

            if hasSelection {
                Button(role: .destructive) {
                    Task { await viewModel.removeSelectedWorktree() }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Remove selected worktree")
            }
        }
    }

    // MARK: - New Worktree Button

    private var newWorktreeButton: some View {
        HStack(spacing: 0) {
            Button(action: { Task { await viewModel.addWorktree() } }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.repository == nil)
            .help("New Worktree")

            if viewModel.isGitHubAvailable {
                Divider()
                    .frame(height: 13)

                Menu {
                    Button("Import from GitHub PR") {
                        openWindow(id: "import-pr")
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 20, height: 22)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .help("More options")
            }
        }
        .foregroundStyle(viewModel.repository == nil ? .tertiary : .primary)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator, lineWidth: 1)
        )
    }

    // MARK: - Action Button

    private func actionButton(
        title: String,
        icon: String,
        isAvailable: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12))
        }
        .disabled(!hasSelection || !isAvailable)
        .help(
            !isAvailable
                ? "\(title) is not installed"
                : !hasSelection
                    ? "Select a worktree first"
                    : "Open in \(title)"
        )
    }
}
