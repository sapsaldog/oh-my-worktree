import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var repoViewModel: RepositoryListViewModel
    @Bindable var worktreeViewModel: WorktreeListViewModel
    @Environment(ShortcutStore.self) var shortcutStore
    @Environment(UpdaterManager.self) private var updaterManager: UpdaterManager?
    @AppStorage("accentColorName") private var accentColorName = AccentChoice.default.rawValue
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 220
    @AppStorage("detailWidth") private var detailWidth: Double = 360
    @State private var repoPendingRemoval: Repository?

    private var accent: Color { AccentChoice.named(accentColorName).color }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ToolbarControls(worktreeVM: worktreeViewModel)
                workspaceRow
                if !repoViewModel.repositories.isEmpty {
                    WindowStatusBar(
                        worktreeViewModel: worktreeViewModel,
                        pathText: statusBarPath,
                        repositoryID: repoViewModel.selectedRepository?.id
                    )
                }
            }
            shortcutButtons
            modalOverlay
        }
        .tint(accent)
        .environment(\.omwAccent, accent)
        .frame(minWidth: 860, minHeight: 520)
        .background(OMWColor.bgWindow)
        .background(MainWindowChromeConfigurator().allowsHitTesting(false))
        // Extend the glass toolbar up under the transparent titlebar so the
        // native traffic lights overlay its left clearance.
        .ignoresSafeArea(.container, edges: .top)
        // Sets the window title used by AppDelegate's "Open Main Window" lookup.
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
        .alert(
            repoPendingRemoval.map { "Remove \u{201C}\($0.name)\u{201D} from Oh My Worktree?" } ?? "",
            isPresented: .init(
                get: { repoPendingRemoval != nil },
                set: { if !$0 { repoPendingRemoval = nil } }
            ),
            presenting: repoPendingRemoval
        ) { repo in
            Button("Remove Repository", role: .destructive) {
                Task { await repoViewModel.removeRepository(repo) }
                repoPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { repoPendingRemoval = nil }
        } message: { _ in
            Text("This removes it from your repository list only. "
                + "The repository and its worktrees stay on disk — nothing is deleted.")
        }
        .task {
            if repoViewModel.repositories.isEmpty {
                await repoViewModel.loadRepositories()
            }
            await worktreeViewModel.windowAppeared(selectedRepository: repoViewModel.selectedRepository)
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

    // MARK: - Workspace layout

    /// Sidebar + (empty state | worktree list + detail). Extracted from `body`
    /// to keep each SwiftUI expression small enough for the type-checker.
    private var workspaceRow: some View {
        HStack(spacing: 0) {
            RepositorySidebar(
                repoVM: repoViewModel,
                width: CGFloat(sidebarWidth),
                selectedWorktreeCount: worktreeViewModel.worktrees.count,
                onSelect: { repo in Task { await repoViewModel.selectRepository(repo) } },
                onAddRepo: { repoViewModel.showingFileDialog = true },
                onSettings: { worktreeViewModel.isShowingSettings = true },
                onCheckUpdates: { updaterManager?.checkForUpdates() },
                onRequestRemove: { repoPendingRemoval = $0 }
            )
            ColumnResizer(width: $sidebarWidth, range: 180...320)
            if repoViewModel.repositories.isEmpty {
                RepositoryEmptyState(
                    onAdd: { repoViewModel.showingFileDialog = true },
                    onDropFolder: { url in
                        Task { await repoViewModel.addRepository(at: url.path(percentEncoded: false)) }
                    }
                )
            } else {
                worktreeColumns
            }
        }
    }

    @ViewBuilder
    private var worktreeColumns: some View {
        WorktreeListColumn(worktreeVM: worktreeViewModel)
        ColumnResizer(width: $detailWidth, range: 300...520, inverted: true)
        DetailPaneView(
            worktree: selectedWorktree,
            isRoot: isRootSelected,
            pullRequest: selectedPullRequest,
            detail: worktreeViewModel.selectedWorktreeDetail,
            tools: detailTools,
            width: CGFloat(detailWidth),
            onOpenPR: {
                if let wt = selectedWorktree { worktreeViewModel.openPullRequest(for: wt) }
            }
        )
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
            tools.append(ActionTool(id: "iterm", name: "iTerm") {
                Task { await worktreeViewModel.openInITerm(wt) }
            })
        }
        if worktreeViewModel.isGhosttyAvailable {
            tools.append(ActionTool(id: "ghostty", name: "Ghostty") {
                Task { await worktreeViewModel.openInGhostty(wt) }
            })
        }
        if worktreeViewModel.isCmuxAvailable {
            tools.append(ActionTool(id: "cmux", name: "cmux") {
                Task { await worktreeViewModel.openInCmux(wt) }
            })
        }
        if worktreeViewModel.isVSCodeAvailable {
            tools.append(ActionTool(id: "vscode", name: "VSCode") {
                Task { await worktreeViewModel.openInVSCode(wt) }
            })
        }
        if worktreeViewModel.isCursorAvailable {
            tools.append(ActionTool(id: "cursor", name: "Cursor") {
                Task { await worktreeViewModel.openInCursor(wt) }
            })
        }
        return tools
    }

    @ViewBuilder
    private var settingsSheet: some View {
        if let updaterManager {
            SettingsSheetContent(
                updaterManager: updaterManager,
                store: shortcutStore,
                onDismiss: { worktreeViewModel.isShowingSettings = false }
            )
        }
    }

    @ViewBuilder
    private var modalOverlay: some View {
        if worktreeViewModel.isShowingCreateSheet {
            glassModal {
                CreateWorktreeSheet(
                    worktreeViewModel: worktreeViewModel,
                    repoName: repoViewModel.selectedRepository?.name ?? "this repository",
                    onDismiss: { worktreeViewModel.isShowingCreateSheet = false }
                )
                .environment(\.omwAccent, accent)
            }
        } else if worktreeViewModel.isShowingSettings {
            glassModal {
                settingsSheet
            }
        } else if worktreeViewModel.isShowingImportPR {
            glassModal {
                ImportPRView(
                    worktreeViewModel: worktreeViewModel,
                    onDismiss: { worktreeViewModel.isShowingImportPR = false }
                )
                .environment(\.omwAccent, accent)
            }
        }
    }

    private func glassModal<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(GlassSheetMetrics.modalScrimOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }

            content()
                .shadow(color: .black.opacity(0.36), radius: 28, y: 18)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .zIndex(20)
    }

    private var shortcutButtons: some View {
        ShortcutButtonsView(
            repoViewModel: repoViewModel,
            worktreeViewModel: worktreeViewModel,
            store: shortcutStore
        )
    }
}

// MARK: - Draggable column divider

/// Thin separator between the sidebar and the list; drag to resize the sidebar.
/// Width is clamped to `range` and persisted by the caller via `@AppStorage`.
private struct ColumnResizer: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// `true` when the resized column is to the *right* of the handle (e.g. the
    /// detail pane): dragging the handle left widens it, so invert the delta.
    var inverted: Bool = false
    @State private var dragStartWidth: Double?

    var body: some View {
        Rectangle()
            .fill(OMWColor.separator)
            .frame(width: 0.5)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 11)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragStartWidth == nil { dragStartWidth = width }
                                let delta = Double(value.translation.width) * (inverted ? -1 : 1)
                                let next = (dragStartWidth ?? width) + delta
                                width = min(max(next, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            }
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

// MARK: - Window chrome bridge

private struct MainWindowChromeConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        view.setAccessibilityElement(false)
        view.onWindowChange = { window in
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }

    final class WindowProbeView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var observerTokens: [NSObjectProtocol] = []

        deinit {
            observerTokens.forEach(NotificationCenter.default.removeObserver)
        }

        func attach(to newWindow: NSWindow?) {
            guard window !== newWindow else { return }
            stopObserving()
            window = newWindow

            guard let newWindow else { return }
            AppDelegate.configureMainWindowChrome(newWindow)
            startObserving(newWindow)
            AppDelegate.centerTrafficLightsAfterLayout(in: newWindow)
        }

        private func startObserving(_ window: NSWindow) {
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didUpdateNotification
            ]
            observerTokens = names.map { name in
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.recenterTrafficLights()
                    }
                }
            }
        }

        private func stopObserving() {
            observerTokens.forEach(NotificationCenter.default.removeObserver)
            observerTokens.removeAll()
        }

        private func recenterTrafficLights() {
            guard let window else { return }
            AppDelegate.centerTrafficLights(in: window)
        }
    }
}
