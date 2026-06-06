import SwiftUI

struct WorktreeRowView: View {
    let worktree: Worktree
    var isRoot: Bool = false
    var pullRequest: PullRequestInfo?
    var jobState: BackgroundJobState?
    var isSelected: Bool = false
    var isRenaming: Bool = false
    var onOpenPullRequest: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onCancelRename: (() -> Void)?

    @Environment(\.omwAccent) private var accent
    @State private var editingName: String = ""
    @State private var didCancelRename = false
    @FocusState private var isTextFieldFocused: Bool

    /// On-accent when the row is selected (prototype: selected-row text is white),
    /// otherwise the supplied base color.
    private func fg(_ base: Color, _ selectedOpacity: Double = 1) -> Color {
        isSelected ? OMWColor.onAccent.opacity(selectedOpacity) : base
    }

    var body: some View {
        HStack(spacing: 11) {
            StatusDot(color: worktree.statusColor(isRoot: isRoot), selected: isSelected)
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
                    .foregroundStyle(fg(OMWColor.labelTertiary, 0.85))
            }
        }
        // Match prototype .wt-row { padding: 9px 12px }.
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // Selection uses the app accent (prototype), not the system-blue highlight.
        .background(isSelected ? accent : Color.clear, in: RoundedRectangle(cornerRadius: OMWRadius.md))
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
                    .foregroundStyle(fg(OMWColor.labelPrimary))
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
                Image("Folder")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(fg(OMWColor.labelSecondary, 0.9))
                Text(worktree.folderName)
                    .font(.system(size: 11))
                    .foregroundStyle(fg(OMWColor.labelSecondary, 0.9))
                    .lineLimit(1)
            }
            if !worktree.commitHash.isEmpty {
                Text("·").foregroundStyle(fg(OMWColor.labelQuaternary, 0.6))
                Text(String(worktree.commitHash.prefix(7)))
                    .font(.omwMono(11))
                    .foregroundStyle(fg(OMWColor.labelTertiary, 0.85))
            }
        }
    }
}
