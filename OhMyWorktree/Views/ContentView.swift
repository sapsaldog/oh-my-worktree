import SwiftUI

struct ContentView: View {
    @ObservedObject var repoViewModel: RepositoryListViewModel
    @ObservedObject var worktreeViewModel: WorktreeListViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Repository selector at top
            RepositorySelectorView(viewModel: repoViewModel)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            // Worktree list in middle
            WorktreeListView(viewModel: worktreeViewModel)
                .frame(maxHeight: .infinity)

            Divider()

            // Action buttons at bottom
            ActionButtonsView(viewModel: worktreeViewModel)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle("Oh My Worktree")
        .alert(
            "Error",
            isPresented: .init(
                get: { repoViewModel.errorMessage != nil || worktreeViewModel.errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        Task { @MainActor in
                            repoViewModel.clearError()
                            worktreeViewModel.clearError()
                        }
                    }
                }
            )
        ) {
            Button("OK") {
                repoViewModel.clearError()
                worktreeViewModel.clearError()
            }
        } message: {
            Text(repoViewModel.errorMessage ?? worktreeViewModel.errorMessage ?? "")
        }
        .task {
            await repoViewModel.loadRepositories()
        }
        .onChange(of: repoViewModel.selectedRepository) { _, newValue in
            Task {
                worktreeViewModel.repository = newValue
                await worktreeViewModel.loadWorktrees()
            }
        }
    }
}

#Preview {
    ContentView(
        repoViewModel: RepositoryListViewModel(),
        worktreeViewModel: WorktreeListViewModel()
    )
}
