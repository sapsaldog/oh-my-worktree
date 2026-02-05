import SwiftUI

struct WorktreeRowView: View {
    let worktree: Worktree

    var body: some View {
        HStack(spacing: 10) {
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(worktree.displayName)
                        .font(.system(.body, design: .default, weight: .medium))
                        .lineLimit(1)

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
}
