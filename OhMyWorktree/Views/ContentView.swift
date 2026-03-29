import SwiftUI

struct ContentView: View {
    @ObservedObject var repoViewModel: RepositoryListViewModel
    @ObservedObject var worktreeViewModel: WorktreeListViewModel

    var body: some View {
        VStack(spacing: 0) {
            RepositorySelectorView(viewModel: repoViewModel)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            WorktreeListView(viewModel: worktreeViewModel)
                .frame(maxHeight: .infinity)

            Divider()

            QueueStatusBarView(viewModel: worktreeViewModel)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle("Oh My Worktree")
        .sheet(isPresented: $worktreeViewModel.isShowingImportPR) {
            ImportPRView(worktreeViewModel: worktreeViewModel)
        }
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
            // On cold start, selectedRepository may already be set by
            // AppDelegate's eager loading, so .onChange won't fire.
            // Sync worktreeViewModel manually in that case.
            if worktreeViewModel.repository == nil, let selected = repoViewModel.selectedRepository {
                worktreeViewModel.repository = selected
                await worktreeViewModel.loadWorktrees()
            }
        }
        .onChange(of: repoViewModel.selectedRepository) { _, newValue in
            Task {
                worktreeViewModel.repository = newValue
                await worktreeViewModel.loadWorktrees()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await worktreeViewModel.loadWorktrees(debounce: true)
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
