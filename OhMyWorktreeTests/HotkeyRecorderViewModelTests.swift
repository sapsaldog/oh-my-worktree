import Carbon.HIToolbox
import XCTest

@testable import OhMyWorktree

final class HotkeyRecorderViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var shortcutManager: ShortcutManager!

    @MainActor
    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "HotkeyRecorderViewModelTests")!
        defaults.removePersistentDomain(forName: "HotkeyRecorderViewModelTests")
        shortcutManager = ShortcutManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "HotkeyRecorderViewModelTests")
        defaults = nil
        shortcutManager = nil
        super.tearDown()
    }

    // MARK: - Initial State

    @MainActor
    func testInitialState_isIdle() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - Recording Transitions

    @MainActor
    func testStartRecording_transitionsToRecording() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        XCTAssertEqual(vm.state, .recording)
    }

    @MainActor
    func testCancelRecording_returnsToIdle() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        vm.cancelRecording()
        XCTAssertEqual(vm.state, .idle)
    }

    @MainActor
    func testHandleKeyCombo_validComboWithModifiers_savesAndReturnsToIdle() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()

        let consumed = vm.handleKey(
            keyCode: UInt16(kVK_ANSI_X),
            modifiers: [.command, .shift]
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(shortcutManager.combo(for: .openSettings), "⇧⌘X")
    }

    @MainActor
    func testHandleKeyCombo_noModifiers_isIgnored() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()

        let consumed = vm.handleKey(keyCode: UInt16(kVK_ANSI_X), modifiers: [])
        XCTAssertFalse(consumed)
        XCTAssertEqual(vm.state, .recording)
    }

    @MainActor
    func testHandleKeyCombo_escapeDuringRecording_cancels() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()

        let consumed = vm.handleKey(keyCode: UInt16(kVK_Escape), modifiers: [])
        XCTAssertTrue(consumed)
        XCTAssertEqual(vm.state, .idle)
        // Original combo should be unchanged
        XCTAssertEqual(shortcutManager.combo(for: .openSettings), "⌘,")
    }

    @MainActor
    func testHandleKeyCombo_deleteDuringRecording_resetsToDefault() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        shortcutManager.setCombo("⌘⇧X", for: .openSettings)
        vm.startRecording()

        let consumed = vm.handleKey(keyCode: UInt16(kVK_Delete), modifiers: [])
        XCTAssertTrue(consumed)
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(shortcutManager.combo(for: .openSettings), "⌘,")
    }

    // MARK: - Conflict Detection

    @MainActor
    func testHandleKeyCombo_conflictDetected_transitionsToConflict() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()

        // "⌘N" is the default for addRepository, so assigning it to openSettings should conflict
        let consumed = vm.handleKey(keyCode: UInt16(kVK_ANSI_N), modifiers: [.command])
        XCTAssertTrue(consumed)

        if case .conflict(let actionName, let combo) = vm.state {
            XCTAssertEqual(combo, "⌘N")
            XCTAssertEqual(actionName, ShortcutAction.addRepository.displayName)
        } else {
            XCTFail("Expected conflict state, got \(vm.state)")
        }
    }

    @MainActor
    func testResolveConflict_override_savesCombo() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        _ = vm.handleKey(keyCode: UInt16(kVK_ANSI_N), modifiers: [.command])

        vm.resolveConflict(override: true)
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(shortcutManager.combo(for: .openSettings), "⌘N")
    }

    @MainActor
    func testResolveConflict_cancel_returnsToRecording() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        _ = vm.handleKey(keyCode: UInt16(kVK_ANSI_N), modifiers: [.command])

        vm.resolveConflict(override: false)
        XCTAssertEqual(vm.state, .recording)
    }

    // MARK: - Display String

    @MainActor
    func testDisplayString_idle_showsCurrentCombo() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        XCTAssertEqual(vm.displayString, "⌘,")
    }

    @MainActor
    func testDisplayString_recording_showsPlaceholder() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        vm.startRecording()
        XCTAssertEqual(vm.displayString, "Type shortcut...")
    }

    // MARK: - Not Recording State

    @MainActor
    func testHandleKey_whenNotRecording_isIgnored() {
        let vm = HotkeyRecorderViewModel(action: .openSettings, shortcutManager: shortcutManager)
        let consumed = vm.handleKey(keyCode: UInt16(kVK_ANSI_X), modifiers: [.command, .shift])
        XCTAssertFalse(consumed)
        XCTAssertEqual(vm.state, .idle)
    }
}
