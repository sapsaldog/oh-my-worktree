import SwiftUI

struct WorktreeRowView: View {
    let worktree: Worktree
    var pullRequest: PullRequestInfo?
    var jobState: BackgroundJobState?
    var isRenaming: Bool = false
    var onOpenPullRequest: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onCancelRename: (() -> Void)?

    @State private var editingName: String = ""
    @State private var didCancelRename = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isRenaming {
                        TextField("", text: $editingName)
                            .font(.system(.body, design: .default, weight: .medium))
                            .textFieldStyle(.plain)
                            .focused($isTextFieldFocused)
                            .onSubmit { onRename?(editingName) }
                            .onExitCommand {
                                didCancelRename = true
                                onCancelRename?()
                            }
                            .onChange(of: isTextFieldFocused) { _, focused in
                                // Commit rename when focus is lost (e.g. clicking away),
                                // but not if the user pressed Esc to cancel.
                                if !focused && !didCancelRename { onRename?(editingName) }
                            }
                            .onAppear {
                                editingName = worktree.customName ?? worktree.displayName
                                didCancelRename = false
                                isTextFieldFocused = true
                            }
                    } else {
                        Text(worktree.displayName)
                            .font(.system(.body, design: .default, weight: .medium))
                            .lineLimit(1)
                    }

                    if let pr = pullRequest { prBadge(pr) }
                    if worktree.isBare { badge("bare", color: .gray) }
                    if worktree.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Locked")
                    }
                    if worktree.isDetached { badge("detached", color: .yellow) }
                }

                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(worktree.folderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !worktree.commitHash.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(String(worktree.commitHash.prefix(7)))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Job state indicator (FR-031)
            if let jobState {
                jobStateIndicator(jobState)
            } else if let relative = worktree.relativeLastActivity {
                Text(relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .opacity(jobState?.isActive == true ? 0.7 : 1.0)
    }

    // MARK: - Job State Indicator

    @ViewBuilder
    private func jobStateIndicator(_ state: BackgroundJobState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Pending")
        case .inProgress:
            ProgressView()
                .scaleEffect(0.65)
                .frame(width: 14, height: 14)
                .accessibilityLabel("In progress")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityLabel("Completed")
        case .failed(let msg):
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .help(msg)
                .accessibilityLabel("Failed: \(msg)")
        case .cancelled:
            Image(systemName: "minus.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Cancelled")
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .accessibilityLabel(statusAccessibilityLabel)
    }

    private var statusAccessibilityLabel: String {
        if worktree.isBare { return "Bare worktree" }
        if worktree.isLocked { return "Locked worktree" }
        if worktree.isDetached { return "Detached HEAD" }
        return "Active worktree"
    }

    private var statusColor: Color {
        if worktree.isBare { return .gray }
        if worktree.isLocked { return .orange }
        if worktree.isDetached { return .yellow }
        return .green
    }

    // MARK: - Badge

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - PR Badge

    private func prBadge(_ pr: PullRequestInfo) -> some View {
        Button(action: { onOpenPullRequest?() }) {
            HStack(spacing: 3) {
                PullRequestStateIcon(state: pr.state, size: 12)
                Text("#\(pr.number)")
                    .font(.system(size: 9, weight: .medium))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(pr.state.color.opacity(0.15))
            .foregroundStyle(pr.state.color)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Open Pull Request #\(pr.number)")
        .accessibilityLabel("Pull Request #\(pr.number), \(pr.state.rawValue)")
    }
}
