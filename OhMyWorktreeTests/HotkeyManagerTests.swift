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
        XCTAssertNil(KeyCombo.from(string: "W"))
        XCTAssertNil(KeyCombo.from(string: "⌥"))
    }

    func testParseKeyCombo_unknownKey_returnsNil() {
        XCTAssertNil(KeyCombo.from(string: "⌥⇧!"))
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

    func testAppSettings_defaultHotkeyCombo() {
        let settings = AppSettings()
        XCTAssertEqual(settings.globalHotkeyKeyCombo, "⌥⇧W")
    }

    func testAppSettings_hotkeySettingsDecodable() throws {
        // Encode a full AppSettings first, then decode to ensure round-trip works
        var original = AppSettings()
        original.globalHotkeyEnabled = false
        original.globalHotkeyKeyCombo = "⌘⇧K"
        let data = try JSONEncoder().encode(original)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertFalse(settings.globalHotkeyEnabled)
        XCTAssertEqual(settings.globalHotkeyKeyCombo, "⌘⇧K")
    }

    func testAppSettings_hotkeySettingsEncodable() throws {
        var settings = AppSettings()
        settings.globalHotkeyEnabled = false
        settings.globalHotkeyKeyCombo = "⌃⌥B"
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertFalse(decoded.globalHotkeyEnabled)
        XCTAssertEqual(decoded.globalHotkeyKeyCombo, "⌃⌥B")
    }
}
