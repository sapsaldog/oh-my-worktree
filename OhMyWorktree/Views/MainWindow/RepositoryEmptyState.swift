import SwiftUI

/// Shown in place of the worktree list + detail when no repositories are tracked.
/// Ports the prototype's `.omw-empty` block: art tile, title, subtitle, a primary
/// pill "Add Repository…" button, and a drop-a-`.git`-folder hint (which is wired
/// to actually add the dropped repository).
struct RepositoryEmptyState: View {
    var onAdd: () -> Void
    var onDropFolder: (URL) -> Void

    @Environment(\.omwAccent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            art
            Text("No Repositories")
                .font(.system(size: 19, weight: .bold))
                .tracking(-0.19)
                .foregroundStyle(OMWColor.labelPrimary)
                .padding(.bottom, 7)
            Text("Add a Git repository and Oh My Worktree will track its branches and worktrees here.")
                .font(.system(size: 13))
                .foregroundStyle(OMWColor.labelSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .frame(maxWidth: 320)
                .padding(.bottom, 22)
            addButton
            hint
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OMWColor.bgWindow)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            onDropFolder(url)
            return true
        }
    }

    /// 84×84 rounded tile with the folder-git glyph (CSS `.empty-art`).
    private var art: some View {
        Image("FolderGit2")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 40, height: 40)
            .foregroundStyle(OMWColor.labelTertiary)
            .frame(width: 84, height: 84)
            .background(OMWColor.fillQuaternary, in: RoundedRectangle(cornerRadius: OMWRadius.xxl))
            .overlay(
                RoundedRectangle(cornerRadius: OMWRadius.xxl)
                    .strokeBorder(OMWColor.separator, lineWidth: 0.5)
            )
            .padding(.bottom, 18)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            HStack(spacing: 7) {
                Image(systemName: "folder.badge.plus").font(.system(size: 15))
                Text("Add Repository…").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(OMWColor.onAccent)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(accent, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var hint: some View {
        (
            Text("or drop a ")
                + Text(".git").font(.omwMono(11.5, weight: .semibold))
                + Text(" folder onto the window")
        )
        .font(.system(size: 11.5))
        .foregroundStyle(OMWColor.labelTertiary)
        .padding(.top, 14)
    }
}
