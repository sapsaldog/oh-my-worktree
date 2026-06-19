import SwiftUI

extension View {
    /// Adds the copied-files status toast (e.g. "Opening … in <tool>").
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
    }
}
