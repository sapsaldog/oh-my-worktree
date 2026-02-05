import SwiftUI

struct ActionButtonsView: View {
    @ObservedObject var viewModel: WorktreeListViewModel

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

            Spacer()

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
