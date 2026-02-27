import SwiftUI

struct WorktreeRowView: View {
    let worktree: Worktree
    var pullRequest: PullRequestInfo?

    var body: some View {
        HStack(spacing: 10) {
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(worktree.displayName)
                        .font(.system(.body, design: .default, weight: .medium))
                        .lineLimit(1)

                    if let pr = pullRequest {
                        prBadge(pr)
                    }

                    if worktree.isBare {
                        badge("bare", color: .gray)
                    }
                    if worktree.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if worktree.isDetached {
                        badge("detached", color: .yellow)
                    }
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

            if let relative = worktree.relativeLastActivity {
                Text(relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        if worktree.isBare {
            return .gray
        } else if worktree.isLocked {
            return .orange
        } else if worktree.isDetached {
            return .yellow
        } else {
            return .green
        }
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
        Button(action: {
            NSWorkspace.shared.open(pr.url)
        }) {
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
    }
}
