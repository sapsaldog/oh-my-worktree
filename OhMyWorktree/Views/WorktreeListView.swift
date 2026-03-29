import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var viewModel: WorktreeListViewModel
    @EnvironmentObject var shortcutManager: ShortcutManager
    @State private var selectedIDs: Set<UUID> = []
    @State private var renamingWorktreeID: UUID?
    @State private var forceRemoveTarget: ForceRemoveTarget?
    @State private var confirmRemoveTarget: Worktree?
    @State private var confirmBulkRemove = false
    @State private var confirmBulkQuickRemove = false
    @State private var quickRemoveTarget: Worktree?

    enum ForceRemoveTarget {
        case single(Worktree)
        case selectedWorktrees(count: Int)
    }

    var body: some View {
        listContent
            .modifier(RemovalDialogsModifier(
                viewModel: viewModel,
                confirmRemoveTarget: $confirmRemoveTarget,
                forceRemoveTarget: $forceRemoveTarget,
                confirmBulkRemove: $confirmBulkRemove,
                confirmBulkQuickRemove: $confirmBulkQuickRemove,
                quickRemoveTarget: $quickRemoveTarget
            ))
    }

    @ViewBuilder
    private var listContent: some View {
        if viewModel.repository == nil {
            emptyStateView(
                icon: "folder.badge.questionmark",
                title: "No Repository Selected",
                subtitle: "Add a repository to get started"
            )
        } else if viewModel.isLoading && viewModel.worktrees.isEmpty {
            ProgressView("Loading worktrees...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.worktrees.isEmpty && !viewModel.jobQueue.hasActiveJobs {
            emptyStateView(
                icon: "tray",
                title: "No Worktrees",
                subtitle: "Click + to create a new worktree"
            )
        } else {
            worktreeList
        }
    }

    // MARK: - Worktree List

    private var worktreeList: some View {
        let jobStates = jobStateByWorktreeID
        return List(selection: $selectedIDs) {
            ForEach(viewModel.worktrees) { worktree in
                worktreeRow(for: worktree, jobStates: jobStates)
                    .tag(worktree.id)
                    .contextMenu {
                        contextMenuItems(for: worktree)
                    }
            }
        }
        .listStyle(.inset)
        .onChange(of: selectedIDs) { _, newIDs in
            guard newIDs != viewModel.selectedWorktreeIDs else { return }
            let vm = viewModel
            Task { @MainActor in vm.selectedWorktreeIDs = newIDs }
        }
        .onChange(of: viewModel.selectedWorktreeIDs) { _, newIDs in
            if newIDs != selectedIDs { selectedIDs = newIDs }
        }
        .onKeyPress(.return) {
            guard renamingWorktreeID == nil,
                  selectedIDs.count == 1,
                  let id = selectedIDs.first,
                  let worktree = viewModel.worktrees.first(where: { $0.id == id })
            else { return .ignored }
            renamingWorktreeID = worktree.id
            return .handled
        }
        .onKeyPress(.escape) {
            guard !selectedIDs.isEmpty else { return .ignored }
            selectedIDs = []
            return .handled
        }
        .onKeyPress(.delete, phases: .down) { press in
            guard !selectedIDs.isEmpty else { return .ignored }
            let mods = press.modifiers
            if mods.contains(.command) && mods.contains(.shift) {
                triggerQuickRemove()
            } else if mods.contains(.command) {
                triggerForceRemove()
            } else {
                triggerRemove()
            }
            return .handled
        }
        .background(TableViewFocuser(worktreeCount: viewModel.worktrees.count))
    }

    private func triggerRemove() {
        if selectedIDs.count >= 2 {
            confirmBulkRemove = true
        } else if let id = selectedIDs.first,
                  let wt = viewModel.worktrees.first(where: { $0.id == id }) {
            confirmRemoveTarget = wt
        }
    }

    private func triggerForceRemove() {
        if selectedIDs.count >= 2 {
            forceRemoveTarget = .selectedWorktrees(count: selectedIDs.count)
        } else if let id = selectedIDs.first,
                  let wt = viewModel.worktrees.first(where: { $0.id == id }) {
            forceRemoveTarget = .single(wt)
        }
    }

    private func triggerQuickRemove() {
        if selectedIDs.count >= 2 {
            confirmBulkQuickRemove = true
        } else if let id = selectedIDs.first,
                  let wt = viewModel.worktrees.first(where: { $0.id == id }) {
            quickRemoveTarget = wt
        }
    }

    // MARK: - Worktree Row

    /// Pre-computed job state lookup to avoid O(N*M) per-row linear scans.
    private var jobStateByWorktreeID: [UUID: BackgroundJobState] {
        var result: [UUID: BackgroundJobState] = [:]
        for job in viewModel.jobQueue.jobs where job.state.isActive {
            result[job.worktreeID] = job.state
        }
        return result
    }

    /// Resolves the PR for a worktree, checking local branch then remote branch fallback.
    private func pullRequest(for worktree: Worktree) -> PullRequestInfo? {
        worktree.branch.flatMap { viewModel.pullRequests[$0] }
            ?? worktree.prRemoteBranch.flatMap { viewModel.pullRequests[$0] }
    }

    private func worktreeRow(for worktree: Worktree, jobStates: [UUID: BackgroundJobState]) -> some View {
        let jobState = jobStates[worktree.id]
        return WorktreeRowView(
            worktree: worktree,
            pullRequest: pullRequest(for: worktree),
            jobState: jobState,
            isRenaming: renamingWorktreeID == worktree.id,
            onOpenPullRequest: { viewModel.openPullRequest(for: worktree) },
            onRename: { newName in
                renamingWorktreeID = nil
                Task { await viewModel.renameWorktree(worktree, newName: newName) }
            },
            onCancelRename: { renamingWorktreeID = nil }
        )
        .help("Right-click for actions")
    }

    // MARK: - Empty State

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for worktree: Worktree) -> some View {
        let actions = viewModel.contextMenuActions(for: worktree)
        let isMultiSelected = viewModel.selectedWorktreeIDs.count >= 2
            && viewModel.selectedWorktreeIDs.contains(worktree.id)

        Button("Rename") { renamingWorktreeID = worktree.id }
            .disabled(!actions.canRename)
            .keyboardShortcut(.return, modifiers: [])

        Divider()

        contextMenuButton("Open in iTerm", action: .openITerm) { Task { await viewModel.openInITerm(worktree) } }
            .disabled(!viewModel.isITermAvailable || !actions.canOpen)
        contextMenuButton("Open in Ghostty", action: .openGhostty) { Task { await viewModel.openInGhostty(worktree) } }
            .disabled(!viewModel.isGhosttyAvailable || !actions.canOpen)
        contextMenuButton("Open in VSCode", action: .openVSCode) { Task { await viewModel.openInVSCode(worktree) } }
            .disabled(!viewModel.isVSCodeAvailable || !actions.canOpen)
        contextMenuButton("Open in Cursor", action: .openCursor) { Task { await viewModel.openInCursor(worktree) } }
            .disabled(!viewModel.isCursorAvailable || !actions.canOpen)
        contextMenuButton("Open in cmux", action: .openCmux) { Task { await viewModel.openInCmux(worktree) } }
            .disabled(!viewModel.isCmuxAvailable || !actions.canOpen)

        if !isMultiSelected, let pr = pullRequest(for: worktree) {
            Divider()
            Button("Open Pull Request #\(pr.number)") { viewModel.openPullRequest(for: worktree) }
        }

        if !worktree.isBare {
            Divider()
            Button("Git Pull") { viewModel.gitPull(worktree) }
                .disabled(!actions.canGitPull)
        }

        Divider()

        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
        }
        .disabled(!actions.canShowInFinder)

        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worktree.path, forType: .string)
        }
        .disabled(!actions.canCopyPath)

        removalMenuItems(for: worktree, actions: actions, isMultiSelected: isMultiSelected)
    }

    @ViewBuilder
    private func contextMenuButton(
        _ title: String,
        action: ShortcutAction,
        perform: @escaping () -> Void
    ) -> some View {
        if let shortcut = shortcutManager.keyboardShortcut(for: action) {
            Button(title, action: perform)
                .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            Button(title, action: perform)
        }
    }

    @ViewBuilder
    private func removalMenuItems(for worktree: Worktree, actions: ContextMenuActions, isMultiSelected: Bool) -> some View {
        if isMultiSelected {
            if actions.canRemove {
                Divider()
                Button("Remove Selected Worktrees", role: .destructive) {
                    confirmBulkRemove = true
                }
                Button("Force Remove Selected Worktrees", role: .destructive) {
                    forceRemoveTarget = .selectedWorktrees(count: viewModel.selectedWorktreeIDs.count)
                }
                Button("Quick Remove Selected Worktrees", role: .destructive) {
                    confirmBulkQuickRemove = true
                }
            }
        } else if let repository = viewModel.repository, !worktree.isRoot(of: repository) {
            Divider()
            Button("Remove Worktree", role: .destructive) {
                confirmRemoveTarget = worktree
            }
            .disabled(!actions.canRemove)
            .keyboardShortcut(.delete, modifiers: [])

            Button("Force Remove Worktree", role: .destructive) {
                forceRemoveTarget = .single(worktree)
            }
            .disabled(!actions.canForceRemove)
            .keyboardShortcut(.delete, modifiers: .command)

            Button("Quick Remove Worktree", role: .destructive) {
                quickRemoveTarget = worktree
            }
            .disabled(!actions.canQuickRemove)
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }

}

// MARK: - Removal Confirmation Dialogs

private struct RemovalDialogsModifier: ViewModifier {
    @ObservedObject var viewModel: WorktreeListViewModel
    @Binding var confirmRemoveTarget: Worktree?
    @Binding var forceRemoveTarget: WorktreeListView.ForceRemoveTarget?
    @Binding var confirmBulkRemove: Bool
    @Binding var confirmBulkQuickRemove: Bool
    @Binding var quickRemoveTarget: Worktree?

    func body(content: Content) -> some View {
        content
            .modifier(SingleRemoveDialog(viewModel: viewModel, target: $confirmRemoveTarget))
            .modifier(ForceRemoveDialog(viewModel: viewModel, target: $forceRemoveTarget))
            .modifier(BulkRemoveDialog(viewModel: viewModel, isPresented: $confirmBulkRemove))
            .modifier(BulkQuickRemoveDialog(viewModel: viewModel, isPresented: $confirmBulkQuickRemove))
            .modifier(SingleQuickRemoveDialog(viewModel: viewModel, target: $quickRemoveTarget))
    }
}

private struct SingleRemoveDialog: ViewModifier {
    @ObservedObject var viewModel: WorktreeListViewModel
    @Binding var target: Worktree?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Remove '\(target?.displayName ?? "")'?",
            isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let wt = target { viewModel.removeWorktree(wt) }
                target = nil
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: {
            Text("Worktrees with uncommitted changes will not be removed.")
        }
    }
}

private struct ForceRemoveDialog: ViewModifier {
    @ObservedObject var viewModel: WorktreeListViewModel
    @Binding var target: WorktreeListView.ForceRemoveTarget?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }),
            titleVisibility: .visible
        ) {
            Button("Force Remove", role: .destructive) {
                switch target {
                case .single(let wt): viewModel.removeWorktree(wt, force: true)
                case .selectedWorktrees: viewModel.removeSelectedWorktrees(force: true)
                case nil: break
                }
                target = nil
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: {
            Text("Uncommitted changes will be lost. This cannot be undone.")
        }
    }

    private var title: String {
        switch target {
        case .single(let wt): "Force Remove '\(wt.displayName)'?"
        case .selectedWorktrees(let n): "Force Remove \(n) Worktree\(n == 1 ? "" : "s")?"
        case nil: ""
        }
    }
}

private struct BulkRemoveDialog: ViewModifier {
    @ObservedObject var viewModel: WorktreeListViewModel
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Remove \(viewModel.selectedWorktreeIDs.count) Worktrees?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { viewModel.removeSelectedWorktrees(force: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Worktrees with uncommitted changes will not be removed.")
        }
    }
}

private struct BulkQuickRemoveDialog: ViewModifier {
    @ObservedObject var viewModel: WorktreeListViewModel
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Quick Remove \(viewModel.selectedWorktreeIDs.count) Worktrees?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Quick Remove", role: .destructive) { viewModel.quickRemoveSelectedWorktrees() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Directories will be moved to Trash. Uncommitted changes will not be checked.")
        }
    }
}

private struct SingleQuickRemoveDialog: ViewModifier {
    @ObservedObject var viewModel: WorktreeListViewModel
    @Binding var target: Worktree?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Quick Remove '\(target?.displayName ?? "")'?",
            isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }),
            titleVisibility: .visible
        ) {
            Button("Quick Remove", role: .destructive) {
                if let wt = target { viewModel.quickRemoveWorktree(wt) }
                target = nil
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: {
            Text("Directory will be moved to Trash. Uncommitted changes will not be checked.")
        }
    }
}

// MARK: - NSTableView Auto-Focus

/// Finds the NSTableView backing a SwiftUI List and makes it the first responder
/// so arrow keys and delete work without requiring a click first.
private struct TableViewFocuser: NSViewRepresentable {
    let worktreeCount: Int

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard worktreeCount > 0 else { return }
        DispatchQueue.main.async {
            guard let window = nsView.window,
                  let tableView = Self.findTableView(in: window.contentView)
            else { return }
            // Only focus if nothing else is currently the first responder
            // (e.g., user is typing in a text field)
            if window.firstResponder === window || window.firstResponder === window.contentView {
                window.makeFirstResponder(tableView)
            }
        }
    }

    private static func findTableView(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let tableView = view as? NSTableView { return tableView }
        for subview in view.subviews {
            if let found = findTableView(in: subview) { return found }
        }
        return nil
    }
}
