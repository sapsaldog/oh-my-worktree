import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var repoViewModel: RepositoryListViewModel
    @Bindable var worktreeViewModel: WorktreeListViewModel
    @Environment(ShortcutStore.self) var shortcutStore
    @AppStorage("accentColorName") private var accentColorName = AccentChoice.default.rawValue

    private var accent: Color { AccentChoice.named(accentColorName).color }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                GlassToolbar(
                    title: repoViewModel.selectedRepository?.name ?? "Oh My Worktree",
                    searchText: $worktreeViewModel.searchText,
                    isRefreshing: worktreeViewModel.isLoading,
                    onImport: { worktreeViewModel.isShowingImportPR = true },
                    onRefresh: { Task { await worktreeViewModel.loadWorktrees() } },
                    onSettings: { openSettings() },
                    onNew: { worktreeViewModel.isShowingCreateSheet = true }
                )

                HStack(spacing: 0) {
                    RepositorySidebar(
                        repoVM: repoViewModel,
                        selectedWorktreeCount: worktreeViewModel.worktrees.count,
                        onSelect: { repo in Task { await repoViewModel.selectRepository(repo) } },
                        onAddRepo: { repoViewModel.showingFileDialog = true },
                        onSettings: { openSettings() },
                        onCheckUpdates: { openSettings() }
                    )
                    WorktreeListColumn(worktreeVM: worktreeViewModel)
                    DetailPaneView(
                        worktree: selectedWorktree,
                        isRoot: isRootSelected,
                        pullRequest: selectedPullRequest,
                        detail: worktreeViewModel.selectedWorktreeDetail,
                        tools: detailTools,
                        onOpenPR: {
                            if let wt = selectedWorktree { worktreeViewModel.openPullRequest(for: wt) }
                        }
                    )
                }

                WindowStatusBar(
                    worktreeViewModel: worktreeViewModel,
                    pathText: statusBarPath,
                    repositoryID: repoViewModel.selectedRepository?.id
                )
            }
            shortcutButtons
        }
        .tint(accent)
        .environment(\.omwAccent, accent)
        .frame(minWidth: 860, minHeight: 520)
        .background(OMWColor.bgWindow)
        .navigationTitle("Oh My Worktree")
        .fileImporter(
            isPresented: $repoViewModel.showingFileDialog,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let path = url.path(percentEncoded: false)
                Task { await repoViewModel.addRepository(at: path) }
            case .failure(let error):
                repoViewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $worktreeViewModel.isShowingImportPR) {
            ImportPRView(worktreeViewModel: worktreeViewModel)
        }
        .sheet(isPresented: $worktreeViewModel.isShowingCreateSheet) {
            CreateWorktreeSheet(
                worktreeViewModel: worktreeViewModel,
                repoName: repoViewModel.selectedRepository?.name ?? "this repository"
            )
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
        .task(id: selectedWorktree?.id) {
            await worktreeViewModel.loadDetail(for: selectedWorktree)
        }
    }

    // MARK: - Derived state

    private var selectedWorktree: Worktree? {
        guard worktreeViewModel.selectedWorktreeIDs.count == 1,
              let id = worktreeViewModel.selectedWorktreeIDs.first else { return nil }
        return worktreeViewModel.worktrees.first { $0.id == id }
    }

    private var selectedPullRequest: PullRequestInfo? {
        guard let wt = selectedWorktree else { return nil }
        return wt.branch.flatMap { worktreeViewModel.pullRequests[$0] }
            ?? wt.prRemoteBranch.flatMap { worktreeViewModel.pullRequests[$0] }
    }

    private var isRootSelected: Bool {
        guard let wt = selectedWorktree, let repo = repoViewModel.selectedRepository else { return false }
        return wt.isRoot(of: repo)
    }

    private var statusBarPath: String {
        selectedWorktree?.path ?? repoViewModel.selectedRepository?.path ?? ""
    }

    private var detailTools: [ActionTool] {
        guard let wt = selectedWorktree else { return [] }
        var tools: [ActionTool] = []
        if worktreeViewModel.isITermAvailable {
            tools.append(ActionTool(id: "iterm", name: "iTerm", systemImage: "terminal") {
                Task { await worktreeViewModel.openInITerm(wt) }
            })
        }
        if worktreeViewModel.isGhosttyAvailable {
            tools.append(ActionTool(id: "ghostty", name: "Ghostty", systemImage: "terminal.fill") {
                Task { await worktreeViewModel.openInGhostty(wt) }
            })
        }
        if worktreeViewModel.isCmuxAvailable {
            tools.append(ActionTool(id: "cmux", name: "cmux", systemImage: "square.grid.3x3") {
                Task { await worktreeViewModel.openInCmux(wt) }
            })
        }
        if worktreeViewModel.isVSCodeAvailable {
            tools.append(ActionTool(id: "vscode", name: "VSCode", systemImage: "chevron.left.forwardslash.chevron.right") {
                Task { await worktreeViewModel.openInVSCode(wt) }
            })
        }
        if worktreeViewModel.isCursorAvailable {
            tools.append(ActionTool(id: "cursor", name: "Cursor", systemImage: "cursorarrow") {
                Task { await worktreeViewModel.openInCursor(wt) }
            })
        }
        return tools
    }

    private func openSettings() {
        (NSApp.delegate as? AppDelegate)?.showOrCreateSettingsWindow()
    }

    private var shortcutButtons: some View {
        ShortcutButtonsView(
            repoViewModel: repoViewModel,
            worktreeViewModel: worktreeViewModel,
            store: shortcutStore
        )
    }
}

// MARK: - Hidden keyboard-shortcut buttons

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
                worktreeViewModel.isShowingCreateSheet = true
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
            shortcutButton(for: .gitPull) {
                guard let worktree = worktreeViewModel.selectedWorktree else { return }
                worktreeViewModel.gitPull(worktree)
            }
            shortcutButton(for: .showInFinder) {
                guard let worktree = worktreeViewModel.selectedWorktree else { return }
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
            }
            shortcutButton(for: .copyPath) {
                guard let worktree = worktreeViewModel.selectedWorktree else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(worktree.path, forType: .string)
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
