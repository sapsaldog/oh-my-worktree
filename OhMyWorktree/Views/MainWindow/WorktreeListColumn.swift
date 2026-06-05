import SwiftUI

/// Middle column: "Worktrees" header + count, then the worktree list.
struct WorktreeListColumn: View {
    var worktreeVM: WorktreeListViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Worktrees")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(OMWColor.labelPrimary)
                Spacer()
                Text(countText)
                    .font(.system(size: 12))
                    .foregroundStyle(OMWColor.labelTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            WorktreeListView(viewModel: worktreeVM)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OMWColor.bgWindow)
    }

    private var countText: String {
        let total = worktreeVM.worktrees.count
        if worktreeVM.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(total) worktree\(total == 1 ? "" : "s")"
        }
        return "\(worktreeVM.filteredWorktrees.count) of \(total) match"
    }
}
