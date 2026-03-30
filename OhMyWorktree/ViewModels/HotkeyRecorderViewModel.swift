import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - ViewModel

/// State machine for keyboard shortcut recording.
@Observable
@MainActor
final class HotkeyRecorderViewModel {

    enum State: Equatable {
        case idle
        case recording
        case conflict(actionName: String, combo: String)
    }

    private(set) var state: State = .idle

    let action: ShortcutAction
    let shortcutManager: ShortcutManager

    /// Combo captured during conflict state, pending user resolution.
    private var pendingCombo: String?
    /// The action that conflicts with the pending combo.
    private var conflictingAction: ShortcutAction?

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
        conflictingAction = nil
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
            conflictingAction = conflicting
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
            // Clear the conflicting action's combo before assigning the new one
            if let conflicting = conflictingAction {
                shortcutManager.setCombo("", for: conflicting)
            }
            shortcutManager.setCombo(combo, for: action)
            pendingCombo = nil
            conflictingAction = nil
            state = .idle
        } else {
            pendingCombo = nil
            conflictingAction = nil
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
