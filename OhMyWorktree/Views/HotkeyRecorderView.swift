import SwiftUI

// MARK: - View

/// A clickable shortcut recorder that captures keyboard input.
struct HotkeyRecorderView: View {
    let action: ShortcutAction
    let shortcutManager: ShortcutManager

    @State private var viewModel: HotkeyRecorderViewModel

    init(action: ShortcutAction, shortcutManager: ShortcutManager) {
        self.action = action
        self.shortcutManager = shortcutManager
        self.viewModel = HotkeyRecorderViewModel(
            action: action, shortcutManager: shortcutManager
        )
    }

    var body: some View {
        HStack {
            Text(viewModel.action.displayName)
            Spacer()
            recorderButton
        }
    }

    @ViewBuilder
    private var recorderButton: some View {
        switch viewModel.state {
        case .idle:
            Button(viewModel.displayString) {
                viewModel.startRecording()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .clipShape(.rect(cornerRadius: 6))
            .font(.system(.body, design: .monospaced))

        case .recording:
            KeyRecordingField(viewModel: viewModel)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.2))
                .clipShape(.rect(cornerRadius: 6))
                .font(.system(.body, design: .monospaced))

        case .conflict(let actionName, let combo):
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(combo) is used by \"\(actionName)\"")
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack(spacing: 8) {
                    Button("Override") { viewModel.resolveConflict(override: true) }
                        .font(.caption)
                    Button("Cancel") { viewModel.resolveConflict(override: false) }
                        .font(.caption)
                }
            }
        }
    }
}
