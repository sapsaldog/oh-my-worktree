import SwiftUI

/// The window's glass top bar, rendered as the first row of the content (under
/// the transparent titlebar via `.fullSizeContentView`), so it shows reliably:
/// native traffic-light clearance · spring · search (230) · import · refresh ·
/// settings · ＋(accent). The native traffic lights overlay the left clearance.
struct ToolbarControls: View {
    @Bindable var worktreeVM: WorktreeListViewModel
    @AppStorage("accentColorName") private var accentColorName = AccentChoice.default.rawValue

    private var accent: Color { AccentChoice.named(accentColorName).color }

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 72, height: 1)   // native traffic-light clearance

            Spacer(minLength: 12)

            searchField.frame(width: 230)

            ToolbarRoundButton(systemImage: "arrow.triangle.pull", assetImage: "GitHubMark",
                               help: "Import from Pull Request") { worktreeVM.isShowingImportPR = true }
            ToolbarRoundButton(systemImage: "arrow.clockwise", help: "Refresh (⌘R)",
                               spinning: worktreeVM.isLoading) { Task { await worktreeVM.loadWorktrees() } }
            ToolbarRoundButton(systemImage: "gearshape", help: "Settings (⌘,)") {
                worktreeVM.isShowingSettings = true
            }
            ToolbarRoundButton(systemImage: "plus", help: "New Worktree (⌘N)", filled: true) {
                worktreeVM.isShowingCreateSheet = true
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(OMWColor.separator).frame(height: 0.5)
        }
        .environment(\.omwAccent, accent)
        .tint(accent)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(OMWColor.labelTertiary)
            TextField("Filter worktrees…", text: $worktreeVM.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(OMWColor.controlBg, in: Capsule())
        .overlay(Capsule().strokeBorder(OMWColor.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
    }
}

/// 30pt round toolbar control chip (solid control-bg; accent-filled for ＋).
struct ToolbarRoundButton: View {
    var systemImage: String
    /// When set, use this template asset (e.g. the GitHub mark) instead of an SF Symbol.
    var assetImage: String?
    var help: String
    var spinning: Bool = false
    var filled: Bool = false
    var action: () -> Void

    @Environment(\.omwAccent) private var accent

    var body: some View {
        Button(action: action) {
            icon
                .foregroundStyle(filled ? OMWColor.onAccent : OMWColor.labelSecondary)
                .frame(width: 30, height: 30)
                .background(filled ? accent : OMWColor.controlBg, in: Circle())
                .overlay {
                    if !filled {
                        Circle().strokeBorder(OMWColor.separator, lineWidth: 0.5)
                    }
                }
                .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    spinning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                    value: spinning
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var icon: some View {
        if let assetImage {
            Image(assetImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: filled ? 15 : 14, weight: .medium))
        }
    }
}
