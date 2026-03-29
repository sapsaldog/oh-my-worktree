import Carbon.HIToolbox
import Testing

@testable import OhMyWorktree

@MainActor
struct HotkeyRecorderViewModelTests {

    let defaults: UserDefaults
    let shortcutManager: ShortcutManager

    init() {
        let suiteName = "HotkeyRecorderViewModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        shortcutManager = ShortcutManager(defaults: defaults)
    }

    // MARK: - Initial State

    @Test func initialState_isIdle() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        #expect(vm.state == .idle)
    }

    // MARK: - Recording Transitions

    @Test func startRecording_transitionsToRecording() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        #expect(vm.state == .recording)
    }

    @Test func cancelRecording_returnsToIdle() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        vm.cancelRecording()
        #expect(vm.state == .idle)
    }

    @Test func handleKeyCombo_validComboWithModifiers_savesAndReturnsToIdle() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()

        let consumed = vm.handleKey(
            keyCode: UInt16(kVK_ANSI_X),
            modifiers: [.command, .shift]
        )

        #expect(consumed)
        #expect(vm.state == .idle)
        #expect(shortcutManager.combo(for: .openSettings) == "⇧⌘X")
    }

    @Test func handleKeyCombo_noModifiers_isIgnored() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()

        let consumed = vm.handleKey(keyCode: UInt16(kVK_ANSI_X), modifiers: [])
        #expect(!consumed)
        #expect(vm.state == .recording)
    }

    @Test func handleKeyCombo_escapeDuringRecording_cancels() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()

        let consumed = vm.handleKey(keyCode: UInt16(kVK_Escape), modifiers: [])
        #expect(consumed)
        #expect(vm.state == .idle)
        #expect(shortcutManager.combo(for: .openSettings) == "⌘,")
    }

    @Test func handleKeyCombo_deleteDuringRecording_resetsToDefault() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        shortcutManager.setCombo("⌘⇧X", for: .openSettings)
        vm.startRecording()

        let consumed = vm.handleKey(keyCode: UInt16(kVK_Delete), modifiers: [])
        #expect(consumed)
        #expect(vm.state == .idle)
        #expect(shortcutManager.combo(for: .openSettings) == "⌘,")
    }

    // MARK: - Conflict Detection

    @Test func handleKeyCombo_conflictDetected_transitionsToConflict() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()

        let consumed = vm.handleKey(keyCode: UInt16(kVK_ANSI_N), modifiers: [.command])
        #expect(consumed)

        guard case .conflict(let actionName, let combo) = vm.state else {
            Issue.record("Expected conflict state, got \(vm.state)")
            return
        }
        #expect(combo == "⌘N")
        #expect(actionName == ShortcutAction.addWorktree.displayName)
    }

    @Test func resolveConflict_override_savesCombo() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        _ = vm.handleKey(keyCode: UInt16(kVK_ANSI_N), modifiers: [.command])

        vm.resolveConflict(override: true)
        #expect(vm.state == .idle)
        #expect(shortcutManager.combo(for: .openSettings) == "⌘N")
    }

    @Test func resolveConflict_cancel_returnsToRecording() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        _ = vm.handleKey(keyCode: UInt16(kVK_ANSI_N), modifiers: [.command])

        vm.resolveConflict(override: false)
        #expect(vm.state == .recording)
    }

    // MARK: - Display String

    @Test func displayString_idle_showsCurrentCombo() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        #expect(vm.displayString == "⌘,")
    }

    @Test func displayString_recording_showsPlaceholder() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        #expect(vm.displayString == "Type shortcut...")
    }

    // MARK: - Override Clears Conflicting Action

    @Test func resolveConflict_override_clearsConflictingActionCombo() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        _ = vm.handleKey(keyCode: UInt16(kVK_ANSI_N), modifiers: [.command])

        vm.resolveConflict(override: true)

        #expect(shortcutManager.combo(for: .openSettings) == "⌘N")
        #expect(shortcutManager.combo(for: .addWorktree) == "")
    }

    // MARK: - Not Recording State

    @Test func handleKey_whenNotRecording_isIgnored() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        let consumed = vm.handleKey(keyCode: UInt16(kVK_ANSI_X), modifiers: [.command, .shift])
        #expect(!consumed)
        #expect(vm.state == .idle)
    }

    // MARK: - resolveConflict When Not In Conflict State

    @Test func resolveConflict_whenIdle_isNoOp() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        #expect(vm.state == .idle)

        vm.resolveConflict(override: true)
        #expect(vm.state == .idle)
        #expect(shortcutManager.combo(for: .openSettings) == "⌘,")
    }

    @Test func resolveConflict_whenRecording_isNoOp() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        #expect(vm.state == .recording)

        vm.resolveConflict(override: false)
        #expect(vm.state == .recording)
    }
}
