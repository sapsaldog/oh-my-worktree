import SwiftUI

/// Renders GitHub-style octicon PR state icons using asset catalog SVGs with appropriate tinting.
struct PullRequestStateIcon: View {
    let state: PullRequestState
    let size: CGFloat

    init(state: PullRequestState, size: CGFloat = 16) {
        self.state = state
        self.size = size
    }

    var body: some View {
        Image(state.imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(state.color)
    }
}

// MARK: - View-layer properties

extension PullRequestState {
    var color: Color {
        switch self {
        case .open: .green
        case .merged: .purple
        case .closed: .red
        }
    }

    var imageName: String {
        switch self {
        case .open: "PROpen"
        case .merged: "PRMerged"
        case .closed: "PRClosed"
        }
    }
}
