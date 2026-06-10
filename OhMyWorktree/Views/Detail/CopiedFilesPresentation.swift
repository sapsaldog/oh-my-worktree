import SwiftUI

extension View {
    /// Adds the copied-files success toast + the apply-to-main confirmation alert.
    /// Extracted from ContentView to keep that file under the length limit.
    func copiedFilesPresentation(_ viewModel: WorktreeListViewModel) -> some View {
        modifier(CopiedFilesPresentation(viewModel: viewModel))
    }
}

private struct CopiedFilesPresentation: ViewModifier {
    var viewModel: WorktreeListViewModel

    func body(content: Content) -> some View {
        content
            .overlay {
                CopiedToast(message: Binding(
                    get: { viewModel.copiedToast },
                    set: { viewModel.copiedToast = $0 }
                ))
            }
            .alert(
                viewModel.pendingApply.map { "Apply \(($0.path as NSString).lastPathComponent) to main?" } ?? "",
                isPresented: Binding(
                    get: { viewModel.pendingApply != nil },
                    set: { if !$0 { viewModel.pendingApply = nil } }
                ),
                presenting: viewModel.pendingApply
            ) { file in
                Button(file.status == .new ? "Copy to main" : "Apply to main", role: .destructive) {
                    let target = viewModel.copiedBrowser?.worktree
                    viewModel.pendingApply = nil
                    if let target {
                        Task { await viewModel.applyCopiedFileToMain(file, in: target) }
                    }
                }
                Button("Cancel", role: .cancel) { viewModel.pendingApply = nil }
            } message: { file in
                Text("Overwrites main's local copy of \(file.path) with this worktree's version. "
                    + "This updates the file on disk only — nothing is committed to Git.")
            }
    }
}
