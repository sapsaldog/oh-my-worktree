import Carbon.HIToolbox
import XCTest

@testable import OhMyWorktree

final class HotkeyManagerTests: XCTestCase {

    // MARK: - KeyCombo Parsing

    func testParseKeyCombo_optionShiftW() {
        let combo = KeyCombo.from(string: "⌥⇧W")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.keyCode, UInt16(kVK_ANSI_W))
        XCTAssertTrue(combo?.modifiers.contains(.option) ?? false)
        XCTAssertTrue(combo?.modifiers.contains(.shift) ?? false)
        XCTAssertFalse(combo?.modifiers.contains(.command) ?? true)
        XCTAssertFalse(combo?.modifiers.contains(.control) ?? true)
    }

    func testParseKeyCombo_commandShiftK() {
        let combo = KeyCombo.from(string: "⌘⇧K")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.keyCode, UInt16(kVK_ANSI_K))
        XCTAssertTrue(combo?.modifiers.contains(.command) ?? false)
        XCTAssertTrue(combo?.modifiers.contains(.shift) ?? false)
    }

    func testParseKeyCombo_controlOptionB() {
        let combo = KeyCombo.from(string: "⌃⌥B")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.keyCode, UInt16(kVK_ANSI_B))
        XCTAssertTrue(combo?.modifiers.contains(.control) ?? false)
        XCTAssertTrue(combo?.modifiers.contains(.option) ?? false)
    }

    func testParseKeyCombo_invalidString_returnsNil() {
        XCTAssertNil(KeyCombo.from(string: ""))
        XCTAssertNil(KeyCombo.from(string: "⌥"))
    }

    func testParseKeyCombo_singleKeyWithoutModifier_parsesSuccessfully() {
        // modifier-less single key is allowed (e.g. "⌫" for delete)
        let combo = KeyCombo.from(string: "W")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.keyCode, UInt16(kVK_ANSI_W))
        XCTAssertTrue(combo?.modifiers.isEmpty ?? false)
    }

    func testParseKeyCombo_unknownKey_returnsNil() {
        XCTAssertNil(KeyCombo.from(string: "⌥⇧!"))
    }

    func testParseKeyCombo_commandComma() {
        let combo = KeyCombo.from(string: "⌘,")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.keyCode, UInt16(kVK_ANSI_Comma))
        XCTAssertTrue(combo?.modifiers.contains(.command) ?? false)
    }

    func testParseKeyCombo_commandBackspace() {
        let combo = KeyCombo.from(string: "⌘⌫")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.keyCode, UInt16(kVK_Delete))
        XCTAssertTrue(combo?.modifiers.contains(.command) ?? false)
    }

    // MARK: - KeyCombo Init from keyCode/modifiers

    func testKeyCombo_initFromKeyCodeAndModifiers_displayStringRoundTrips() {
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_W), modifiers: [.option, .shift])
        XCTAssertEqual(combo.displayString, "⌥⇧W")
    }

    func testKeyCombo_commaDisplayString_roundTrips() {
        let combo = KeyCombo.from(string: "⌘,")
        XCTAssertEqual(combo?.displayString, "⌘,")
    }

    func testKeyCombo_backspaceDisplayString_roundTrips() {
        let combo = KeyCombo.from(string: "⌘⌫")
        XCTAssertEqual(combo?.displayString, "⌘⌫")
    }

    // MARK: - KeyCombo Display String

    func testKeyComboDisplayString_roundTrips() {
        let original = "⌥⇧W"
        let combo = KeyCombo.from(string: original)
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.displayString, original)
    }

    // MARK: - HotkeyManager Lifecycle

    @MainActor
    func testHotkeyManager_initialState_isNotRegistered() {
        let manager = HotkeyManager()
        XCTAssertFalse(manager.isRegistered)
    }

    @MainActor
    func testHotkeyManager_registerWithValidCombo_becomesRegistered() {
        let manager = HotkeyManager()
        manager.register(keyCombo: "⌥⇧W") { }
        XCTAssertTrue(manager.isRegistered)
    }

    @MainActor
    func testHotkeyManager_registerWithInvalidCombo_staysUnregistered() {
        let manager = HotkeyManager()
        manager.register(keyCombo: "") { }
        XCTAssertFalse(manager.isRegistered)
    }

    @MainActor
    func testHotkeyManager_unregister_becomesUnregistered() {
        let manager = HotkeyManager()
        manager.register(keyCombo: "⌥⇧W") { }
        XCTAssertTrue(manager.isRegistered)

        manager.unregister()
        XCTAssertFalse(manager.isRegistered)
    }

    @MainActor
    func testHotkeyManager_reRegister_updatesCombo() {
        let manager = HotkeyManager()
        manager.register(keyCombo: "⌥⇧W") { }
        XCTAssertTrue(manager.isRegistered)

        // Re-register with a different combo
        manager.register(keyCombo: "⌘⇧K") { }
        XCTAssertTrue(manager.isRegistered)
    }

    @MainActor
    func testHotkeyManager_enableDisable() {
        let manager = HotkeyManager()
        manager.register(keyCombo: "⌥⇧W") { }
        XCTAssertTrue(manager.isRegistered)

        manager.setEnabled(false)
        XCTAssertFalse(manager.isRegistered)

        manager.setEnabled(true)
        XCTAssertTrue(manager.isRegistered)
    }

    @MainActor
    func testHotkeyManager_disableWithoutPriorRegistration_staysUnregistered() {
        let manager = HotkeyManager()
        manager.setEnabled(false)
        XCTAssertFalse(manager.isRegistered)

        // Enabling without a combo should not register
        manager.setEnabled(true)
        XCTAssertFalse(manager.isRegistered)
    }

    // MARK: - AppSettings Defaults

    func testAppSettings_defaultHotkeyEnabled() {
        let settings = AppSettings()
        XCTAssertTrue(settings.globalHotkeyEnabled)
    }

    func testAppSettings_hotkeyEnabledRoundTrip() throws {
        var original = AppSettings()
        original.globalHotkeyEnabled = false
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertFalse(decoded.globalHotkeyEnabled)
    }
}
