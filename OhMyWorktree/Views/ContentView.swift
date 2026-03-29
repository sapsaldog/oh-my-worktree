import SwiftUI

struct ContentView: View {
    @ObservedObject var repoViewModel: RepositoryListViewModel
    @ObservedObject var worktreeViewModel: WorktreeListViewModel
    @EnvironmentObject var shortcutManager: ShortcutManager

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
            if repoViewModel.repositories.isEmpty {
                await repoViewModel.loadRepositories()
            }
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

    // MARK: - Main Content

    private var mainContent: some View {
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

    // MARK: - Keyboard Shortcut Buttons

    /// Invisible buttons that register dynamic keyboard shortcuts with the responder chain.
    @ViewBuilder
    private var shortcutButtons: some View {
        // Use shortcutManager.version to force re-evaluation when shortcuts change
        // swiftlint:disable:next redundant_discardable_let
        let _ = shortcutManager.version

        Group {
            shortcutButton(for: .openSettings) {
                (NSApp.delegate as? AppDelegate)?.showOrCreateSettingsWindow()
            }
            shortcutButton(for: .addRepository) {
                repoViewModel.showingFileDialog = true
            }
            shortcutButton(for: .addWorktree) {
                Task { await worktreeViewModel.addWorktree() }
            }
            shortcutButton(for: .removeWorktree) {
                worktreeViewModel.removeSelectedWorktrees(force: false)
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
        if let shortcut = shortcutManager.keyboardShortcut(for: action) {
            Button("", action: perform)
                .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        }
    }

    private func openSelectedWorktree(
        action: @escaping @MainActor (WorktreeListViewModel, Worktree) async -> Void
    ) {
        guard let worktree = worktreeViewModel.selectedWorktree else { return }
        Task { await action(worktreeViewModel, worktree) }
    }
}
