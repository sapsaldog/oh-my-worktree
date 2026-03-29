import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - ViewModel

/// State machine for keyboard shortcut recording.
@MainActor
final class HotkeyRecorderViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case recording
        case conflict(actionName: String, combo: String)
    }

    @Published private(set) var state: State = .idle

    let action: ShortcutAction
    let shortcutManager: ShortcutManager

    /// Combo captured during conflict state, pending user resolution.
    private var pendingCombo: String?

    init(action: ShortcutAction, shortcutManager: ShortcutManager) {
        self.action = action
        self.shortcutManager = shortcutManager
    }

    // MARK: - Public API

    func startRecording() {
        state = .recording
    }

    func cancelRecording() {
        pendingCombo = nil
        state = .idle
    }

    /// Processes a key event during recording. Returns true if the event was consumed.
    func handleKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard state == .recording else { return false }

        // ESC → cancel
        if keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return true
        }

        // Delete/Backspace without modifiers → reset to default
        let relevantModifiers = modifiers.intersection([.command, .option, .shift, .control])
        if keyCode == UInt16(kVK_Delete) && relevantModifiers.isEmpty {
            shortcutManager.resetToDefault(action)
            state = .idle
            return true
        }

        // Require at least one modifier for a valid shortcut
        guard !relevantModifiers.isEmpty else { return false }

        let combo = KeyCombo(keyCode: keyCode, modifiers: relevantModifiers)
        let comboString = combo.displayString

        // Check for conflicts
        if let conflicting = shortcutManager.conflictingAction(for: comboString, excluding: action) {
            pendingCombo = comboString
            state = .conflict(actionName: conflicting.displayName, combo: comboString)
            return true
        }

        // No conflict — save immediately
        shortcutManager.setCombo(comboString, for: action)
        state = .idle
        return true
    }

    func resolveConflict(override: Bool) {
        guard case .conflict = state, let combo = pendingCombo else { return }
        if override {
            shortcutManager.setCombo(combo, for: action)
            pendingCombo = nil
            state = .idle
        } else {
            pendingCombo = nil
            state = .recording
        }
    }

    var displayString: String {
        switch state {
        case .idle:
            return shortcutManager.combo(for: action)
        case .recording:
            return "Type shortcut..."
        case .conflict(_, let combo):
            return combo
        }
    }
}

// MARK: - View

/// A clickable shortcut recorder that captures keyboard input.
struct HotkeyRecorderView: View {
    @ObservedObject var viewModel: HotkeyRecorderViewModel

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
            .cornerRadius(6)
            .font(.system(.body, design: .monospaced))

        case .recording:
            KeyRecordingField(viewModel: viewModel)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.2))
                .cornerRadius(6)
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

// MARK: - Key Recording NSView Bridge

/// An NSViewRepresentable that captures raw key events during recording mode.
struct KeyRecordingField: NSViewRepresentable {
    let viewModel: HotkeyRecorderViewModel

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyEvent = { [weak viewModel] keyCode, modifiers in
            _ = viewModel?.handleKey(keyCode: keyCode, modifiers: modifiers)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {}
}

/// A custom NSView that becomes first responder to capture key events.
final class KeyCaptureView: NSView {
    var onKeyEvent: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        onKeyEvent?(event.keyCode, event.modifierFlags)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw the placeholder text
        let text = "Type shortcut..."
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        text.draw(in: dirtyRect, withAttributes: attributes)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 120, height: 20)
    }
}
