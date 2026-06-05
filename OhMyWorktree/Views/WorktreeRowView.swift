import SwiftUI

struct WorktreeRowView: View {
    let worktree: Worktree
    var isRoot: Bool = false
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
        HStack(spacing: 11) {
            StatusDot(color: worktree.statusColor(isRoot: isRoot))
                .accessibilityLabel(worktree.statusLabel(isRoot: isRoot))

            VStack(alignment: .leading, spacing: 3) {
                line1
                line2
            }

            Spacer(minLength: 8)

            if let jobState {
                JobIndicator(state: jobState)
            } else if let relative = worktree.relativeLastActivity {
                Text(relative)
                    .font(.system(size: 11))
                    .foregroundStyle(OMWColor.labelTertiary)
            }
        }
        .padding(.vertical, 3)
        .opacity(jobState?.isActive == true ? 0.7 : 1.0)
    }

    @ViewBuilder
    private var line1: some View {
        HStack(spacing: 7) {
            if isRenaming {
                TextField("", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($isTextFieldFocused)
                    .onSubmit { onRename?(editingName) }
                    .onExitCommand {
                        didCancelRename = true
                        onCancelRename?()
                    }
                    .onChange(of: isTextFieldFocused) { _, focused in
                        if !focused && !didCancelRename { onRename?(editingName) }
                    }
                    .onAppear {
                        editingName = worktree.customName ?? worktree.displayName
                        didCancelRename = false
                        isTextFieldFocused = true
                    }
            } else {
                Text(worktree.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }

            if let pr = pullRequest {
                Button { onOpenPullRequest?() } label: {
                    PRBadge(state: pr.state, number: pr.number)
                }
                .buttonStyle(.plain)
                .help("Open Pull Request #\(pr.number)")
                if pr.isDraft { OMWBadge.draft }
            }
            if worktree.isLocked { OMWBadge.locked }
            if worktree.isDetached { OMWBadge.detached }
            if worktree.isBare { OMWBadge.bare }
            if isRoot && !worktree.isBare { OMWBadge.main }
        }
    }

    private var line2: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(OMWColor.labelSecondary)
                Text(worktree.folderName)
                    .font(.system(size: 11))
                    .foregroundStyle(OMWColor.labelSecondary)
                    .lineLimit(1)
            }
            if !worktree.commitHash.isEmpty {
                Text("·").foregroundStyle(OMWColor.labelQuaternary)
                Text(String(worktree.commitHash.prefix(7)))
                    .font(.omwMono(11))
                    .foregroundStyle(OMWColor.labelTertiary)
            }
        }
    }
}
