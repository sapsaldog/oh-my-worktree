import SwiftUI

/// A launchable external tool for the detail pane action bar.
/// `id` selects the prototype's bundled `tool-{id}` icon asset.
struct ActionTool: Identifiable {
    let id: String
    let name: String
    let open: () -> Void
}

/// Right column (360): scrollable detail (hero · meta · PR · diff · commits) +
/// pinned glass "Open in" action bar.
struct DetailPaneView: View {
    var worktree: Worktree?
    var isRoot: Bool
    var pullRequest: PullRequestInfo?
    var detail: WorktreeDetail?
    var tools: [ActionTool]
    var width: CGFloat
    var onOpenPR: () -> Void
    var onOpenCopiedDiff: (CopiedFile) -> Void = { _ in }
    var onBrowseCopied: () -> Void = {}

    @Environment(\.omwAccent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            if let worktree {
                ScrollView { content(worktree) }
                actionBar(worktree)
            } else {
                emptyState
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(OMWColor.bgGrouped)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(OMWColor.labelQuaternary)
            Text("No worktree selected")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OMWColor.labelSecondary)
            Text("Select a worktree to see its details, pull request, and recent commits.")
                .font(.system(size: 12))
                .foregroundStyle(OMWColor.labelTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ wt: Worktree) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            hero(wt)
            metaGrid(wt).padding(.init(top: 14, leading: 18, bottom: 14, trailing: 18))
            if let pr = pullRequest { prSection(pr) }
            if let diff = detail?.diff, !diff.isEmpty {
                section("Changes vs. base") { DiffStatBar(added: diff.added, removed: diff.removed, files: diff.files) }
            }
            if let commits = detail?.commits, !commits.isEmpty {
                section("Recent commits") { commitList(commits) }
            }
            if let copied = detail?.copiedFiles, !copied.isEmpty {
                CopiedFilesSection(files: copied, onOpenDiff: onOpenCopiedDiff, onBrowseAll: onBrowseCopied)
            }
        }
    }

    private func hero(_ wt: Worktree) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(wt.statusColor(isRoot: isRoot))
                    .frame(width: 11, height: 11)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(wt.displayName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(OMWColor.labelPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        Image(systemName: "folder").font(.system(size: 12))
                        Text(wt.folderName)
                        if !wt.commitHash.isEmpty {
                            Text("·").foregroundStyle(OMWColor.labelQuaternary)
                            Text(String(wt.commitHash.prefix(7))).font(.omwMono(12))
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(OMWColor.labelSecondary)
                }
            }
            HStack(spacing: 6) {
                OMWBadge.gray(wt.statusLabel(isRoot: isRoot))
                if let pr = pullRequest {
                    PRBadge(state: pr.state, number: pr.number)
                    if pr.isDraft { OMWBadge.draft }
                }
                if wt.isLocked { OMWBadge.locked }
            }
        }
        .padding(.init(top: 18, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(OMWColor.separator).frame(height: 0.5) }
    }

    // MARK: - Meta grid

    private func metaGrid(_ wt: Worktree) -> some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                metaCell("Branch", wt.branch ?? "—", mono: true)
                metaCell("Commit", String(wt.commitHash.prefix(7)), mono: true)
            }
            GridRow {
                metaCellContainer("Ahead / Behind") { aheadBehindValue }
                metaCell("Last activity", wt.relativeLastActivity ?? "—")
            }
        }
        .background(OMWColor.separator)
        .clipShape(RoundedRectangle(cornerRadius: OMWRadius.md))
        .overlay(RoundedRectangle(cornerRadius: OMWRadius.md).strokeBorder(OMWColor.separator, lineWidth: 0.5))
    }

    @ViewBuilder
    private var aheadBehindValue: some View {
        if let ab = detail?.aheadBehind {
            HStack(spacing: 8) {
                Label("\(ab.ahead)", systemImage: "arrow.up")
                Label("\(ab.behind)", systemImage: "arrow.down")
            }
            .labelStyle(.titleAndIcon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OMWColor.labelPrimary)
        } else {
            Text("—").font(.system(size: 13, weight: .semibold)).foregroundStyle(OMWColor.labelPrimary)
        }
    }

    private func metaCell(_ key: String, _ value: String, mono: Bool = false) -> some View {
        metaCellContainer(key) {
            Text(value)
                .font(mono ? .omwMono(13, weight: .medium) : .system(size: 13, weight: .semibold))
                .foregroundStyle(OMWColor.labelPrimary)
                .lineLimit(1)
        }
    }

    private func metaCellContainer<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.3)
                .foregroundStyle(OMWColor.labelTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(OMWColor.bgRaised)
    }

    // MARK: - PR section

    private func prSection(_ pr: PullRequestInfo) -> some View {
        section("Pull Request") {
            Button(action: onOpenPR) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        Text("#\(pr.number)").font(.omwMono(13, weight: .bold)).foregroundStyle(pr.state.color)
                        PRBadge(state: pr.state, number: pr.number)
                        if pr.isDraft { OMWBadge.draft }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(OMWColor.labelTertiary)
                    }
                    if !pr.title.isEmpty {
                        Text(pr.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(OMWColor.labelPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    prMetaRow(pr)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OMWColor.bgRaised, in: RoundedRectangle(cornerRadius: OMWRadius.md))
                .overlay(RoundedRectangle(cornerRadius: OMWRadius.md).strokeBorder(OMWColor.separator, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func prMetaRow(_ pr: PullRequestInfo) -> some View {
        HStack(spacing: 12) {
            if !pr.author.isEmpty {
                Text("by @\(pr.author)").foregroundStyle(OMWColor.labelSecondary)
            }
            if let review = pr.reviewDecision.summary {
                Text(review).foregroundStyle(OMWColor.labelSecondary)
            }
            if let checks = pr.checkStatus.label {
                HStack(spacing: 3) {
                    Image(systemName: pr.checkStatus.systemImage)
                    Text("checks \(checks)")
                }
                .foregroundStyle(pr.checkStatus.color)
            }
        }
        .font(.system(size: 11))
    }

    // MARK: - Commits

    private func commitList(_ commits: [Commit]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                if index > 0 {
                    Rectangle().fill(OMWColor.separator).frame(height: 0.5)
                }
                commitRow(commit)
            }
        }
    }

    private func commitRow(_ commit: Commit) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(commit.hash)
                .font(.omwMono(11, weight: .medium))
                .foregroundStyle(accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OMWColor.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(commitMeta(commit))
                    .font(.system(size: 10))
                    .foregroundStyle(OMWColor.labelTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

    private func commitMeta(_ commit: Commit) -> String {
        if let when = commit.date?.relativeTimeString {
            return "\(commit.author) · \(when)"
        }
        return commit.author
    }

    // MARK: - Section wrapper

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.3)
                .foregroundStyle(OMWColor.labelTertiary)
            content()
        }
        .padding(.init(top: 14, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(OMWColor.separator).frame(height: 0.5) }
    }

    // MARK: - Action bar

    private func actionBar(_ wt: Worktree) -> some View {
        HStack(spacing: 10) {
            Text("Open in")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.3)
                .foregroundStyle(OMWColor.labelTertiary)
            Spacer()
            HStack(spacing: 7) {
                ForEach(tools) { tool in
                    Button(action: tool.open) {
                        ToolIcon(toolID: tool.id)
                    }
                    .buttonStyle(.plain)
                    .help("Open in \(tool.name)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: Rectangle())
        .overlay(alignment: .top) { Rectangle().fill(OMWColor.separator).frame(height: 0.5) }
        .disabled(wt.isDetached)
        .opacity(wt.isDetached ? 0.5 : 1)
    }
}
