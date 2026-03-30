import SwiftUI

// MARK: - Removal Confirmation Dialogs

struct RemovalDialogsModifier: ViewModifier {
    var viewModel: WorktreeListViewModel
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
    var viewModel: WorktreeListViewModel
    @Binding var target: Worktree?

    func body(content: Content) -> some View {
        content.alert(
            "Remove '\(target?.displayName ?? "")'?",
            isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })
        ) {
            Button("Remove", role: .destructive) {
                if let wt = target { viewModel.removeWorktree(wt) }
                target = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { target = nil }
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("Worktrees with uncommitted changes will not be removed.")
        }
    }
}

private struct ForceRemoveDialog: ViewModifier {
    var viewModel: WorktreeListViewModel
    @Binding var target: WorktreeListView.ForceRemoveTarget?

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })
        ) {
            Button("Force Remove", role: .destructive) {
                switch target {
                case .single(let wt): viewModel.removeWorktree(wt, force: true)
                case .selectedWorktrees: viewModel.removeSelectedWorktrees(force: true)
                case nil: break
                }
                target = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { target = nil }
                .keyboardShortcut(.cancelAction)
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
    var viewModel: WorktreeListViewModel
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert(
            "Remove \(viewModel.selectedWorktreeIDs.count) Worktrees?",
            isPresented: $isPresented
        ) {
            Button("Remove", role: .destructive) { viewModel.removeSelectedWorktrees(force: false) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("Worktrees with uncommitted changes will not be removed.")
        }
    }
}

private struct BulkQuickRemoveDialog: ViewModifier {
    var viewModel: WorktreeListViewModel
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert(
            "Quick Remove \(viewModel.selectedWorktreeIDs.count) Worktrees?",
            isPresented: $isPresented
        ) {
            Button("Quick Remove", role: .destructive) { viewModel.quickRemoveSelectedWorktrees() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("Directories will be moved to Trash. Uncommitted changes will not be checked.")
        }
    }
}

private struct SingleQuickRemoveDialog: ViewModifier {
    var viewModel: WorktreeListViewModel
    @Binding var target: Worktree?

    func body(content: Content) -> some View {
        content.alert(
            "Quick Remove '\(target?.displayName ?? "")'?",
            isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })
        ) {
            Button("Quick Remove", role: .destructive) {
                if let wt = target { viewModel.quickRemoveWorktree(wt) }
                target = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { target = nil }
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("Directory will be moved to Trash. Uncommitted changes will not be checked.")
        }
    }
}
