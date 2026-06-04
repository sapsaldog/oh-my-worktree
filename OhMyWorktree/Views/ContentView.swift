import SwiftUI

struct ContentView: View {
    var repoViewModel: RepositoryListViewModel
    @Bindable var worktreeViewModel: WorktreeListViewModel
    @Environment(ShortcutStore.self) var shortcutStore

    var body: some View {
        ZStack {
            mainContent
            shortcutButtons
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
                        repoViewModel.clearError()
                        worktreeViewModel.clearError()
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
            if repoViewModel.repositories.isEmpty {
                await repoViewModel.loadRepositories()
            }
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

    private var mainContent: some View {
        MainContentView(repoViewModel: repoViewModel, worktreeViewModel: worktreeViewModel)
    }

    private var shortcutButtons: some View {
        ShortcutButtonsView(
            repoViewModel: repoViewModel,
            worktreeViewModel: worktreeViewModel,
            store: shortcutStore
        )
    }
}

// MARK: - Subviews

private struct MainContentView: View {
    var repoViewModel: RepositoryListViewModel
    var worktreeViewModel: WorktreeListViewModel

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
    }
}

private struct ShortcutButtonsView: View {
    var repoViewModel: RepositoryListViewModel
    var worktreeViewModel: WorktreeListViewModel
    var store: ShortcutStore

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = store.version

        Group {
            shortcutButton(for: .addRepository) {
                repoViewModel.showingFileDialog = true
            }
            shortcutButton(for: .addWorktree) {
                Task { await worktreeViewModel.addWorktree() }
            }
            shortcutButton(for: .removeWorktree) {
                worktreeViewModel.pendingDelete = .remove
            }
            shortcutButton(for: .forceRemoveWorktree) {
                worktreeViewModel.pendingDelete = .forceRemove
            }
            shortcutButton(for: .quickRemoveWorktree) {
                worktreeViewModel.pendingDelete = .quickRemove
            }
            shortcutButton(for: .openITerm) {
                openSelectedWorktree { vm, wt in await vm.openInITerm(wt) }
            }
            shortcutButton(for: .openGhostty) {
                openSelectedWorktree { vm, wt in await vm.openInGhostty(wt) }
            }
            shortcutButton(for: .openVSCode) {
                openSelectedWorktree { vm, wt in await vm.openInVSCode(wt) }
            }
            shortcutButton(for: .openCursor) {
                openSelectedWorktree { vm, wt in await vm.openInCursor(wt) }
            }
            shortcutButton(for: .openCmux) {
                openSelectedWorktree { vm, wt in await vm.openInCmux(wt) }
            }
            shortcutButton(for: .refreshWorktrees) {
                Task { await worktreeViewModel.loadWorktrees() }
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func shortcutButton(for action: ShortcutAction, perform: @escaping () -> Void) -> some View {
        Button(action.displayName, action: perform)
            .keyboardShortcut(store.swiftUIShortcut(for: action))
    }

    private func openSelectedWorktree(
        action: @escaping @MainActor (WorktreeListViewModel, Worktree) async -> Void
    ) {
        guard let worktree = worktreeViewModel.selectedWorktree else { return }
        Task { await action(worktreeViewModel, worktree) }
    }
}
