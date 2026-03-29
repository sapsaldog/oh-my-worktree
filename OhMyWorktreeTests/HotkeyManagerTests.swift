import Carbon.HIToolbox
import Testing

@testable import OhMyWorktree

struct HotkeyManagerTests {

    // MARK: - KeyCombo Parsing (parameterized)

    @Test(arguments: [
        ("⌥⇧W", UInt16(kVK_ANSI_W)),
        ("⌘⇧K", UInt16(kVK_ANSI_K)),
        ("⌃⌥B", UInt16(kVK_ANSI_B)),
        ("⌘,", UInt16(kVK_ANSI_Comma)),
        ("⌘⌫", UInt16(kVK_Delete))
    ])
    func parseKeyCombo_validInputs(input: String, expectedKeyCode: UInt16) throws {
        let combo = try #require(KeyCombo.from(string: input))
        #expect(combo.keyCode == expectedKeyCode)
    }

    @Test func parseKeyCombo_optionShiftW_modifiers() throws {
        let combo = try #require(KeyCombo.from(string: "⌥⇧W"))
        #expect(combo.modifiers.contains(.option))
        #expect(combo.modifiers.contains(.shift))
        #expect(!combo.modifiers.contains(.command))
        #expect(!combo.modifiers.contains(.control))
    }

    @Test func parseKeyCombo_commandShiftK_modifiers() throws {
        let combo = try #require(KeyCombo.from(string: "⌘⇧K"))
        #expect(combo.modifiers.contains(.command))
        #expect(combo.modifiers.contains(.shift))
    }

    @Test func parseKeyCombo_controlOptionB_modifiers() throws {
        let combo = try #require(KeyCombo.from(string: "⌃⌥B"))
        #expect(combo.modifiers.contains(.control))
        #expect(combo.modifiers.contains(.option))
    }

    @Test(arguments: ["", "⌥"])
    func parseKeyCombo_invalidString_returnsNil(input: String) {
        #expect(KeyCombo.from(string: input) == nil)
    }

    @Test func parseKeyCombo_singleKeyWithoutModifier_parsesSuccessfully() throws {
        let combo = try #require(KeyCombo.from(string: "W"))
        #expect(combo.keyCode == UInt16(kVK_ANSI_W))
        #expect(combo.modifiers.isEmpty)
    }

    @Test func parseKeyCombo_unknownKey_returnsNil() {
        #expect(KeyCombo.from(string: "⌥⇧!") == nil)
    }

    // MARK: - KeyCombo Init from keyCode/modifiers

    @Test func keyCombo_initFromKeyCodeAndModifiers_displayStringRoundTrips() {
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_W), modifiers: [.option, .shift])
        #expect(combo.displayString == "⌥⇧W")
    }

    @Test func keyCombo_commaDisplayString_roundTrips() throws {
        let combo = try #require(KeyCombo.from(string: "⌘,"))
        #expect(combo.displayString == "⌘,")
    }

    @Test func keyCombo_backspaceDisplayString_roundTrips() throws {
        let combo = try #require(KeyCombo.from(string: "⌘⌫"))
        #expect(combo.displayString == "⌘⌫")
    }

    // MARK: - KeyCombo Display String

    @Test func keyComboDisplayString_roundTrips() throws {
        let original = "⌥⇧W"
        let combo = try #require(KeyCombo.from(string: original))
        #expect(combo.displayString == original)
    }

    @Test func keyComboDisplayString_allFourModifiers_roundTrips() throws {
        let original = "⌃⌥⇧⌘W"
        let combo = try #require(KeyCombo.from(string: original))
        #expect(combo.modifiers.contains(.control))
        #expect(combo.modifiers.contains(.option))
        #expect(combo.modifiers.contains(.shift))
        #expect(combo.modifiers.contains(.command))
        #expect(combo.displayString == original)
    }

    @Test func keyComboDisplayString_modifierOrder_isCanonical() throws {
        let combo = try #require(KeyCombo.from(string: "⌘⌃⇧⌥A"))
        #expect(combo.displayString == "⌃⌥⇧⌘A")
    }

    // MARK: - KeyMapping Single Source of Truth

    @Test func keyMapping_allKeys_coversAllKeyCodeMapEntries() {
        let derivedMap = KeyCombo.keyCodeMap
        let allKeyDisplayChars = Set(KeyCombo.allKeys.map(\.displayChar))
        for key in derivedMap.keys {
            #expect(allKeyDisplayChars.contains(key), "keyCodeMap key '\(key)' not in allKeys")
        }
        #expect(derivedMap.count == KeyCombo.allKeys.count)
    }

    @Test func keyMapping_allKeys_coversAllSwiftUICharacterMapEntries() {
        let derivedMap = KeyCombo.keyCodeToSwiftUICharacter
        let allKeyCodes = Set(KeyCombo.allKeys.map(\.keyCode))
        for keyCode in derivedMap.keys {
            #expect(allKeyCodes.contains(keyCode), "keyCodeToSwiftUICharacter code \(keyCode) not in allKeys")
        }
        #expect(derivedMap.count == KeyCombo.allKeys.count)
    }

    @Test func keyMapping_allKeys_noDuplicateKeyCodes() {
        let keyCodes = KeyCombo.allKeys.map(\.keyCode)
        #expect(keyCodes.count == Set(keyCodes).count, "Duplicate key codes in allKeys")
    }

    @Test func keyMapping_allKeys_noDuplicateDisplayChars() {
        let displayChars = KeyCombo.allKeys.map(\.displayChar)
        #expect(displayChars.count == Set(displayChars).count, "Duplicate display chars in allKeys")
    }

    @Test func keyMapping_derivedMaps_coverSameKeyCodes() {
        let fromKeyCodeMap = Set(KeyCombo.keyCodeMap.values)
        let fromCharacterMap = Set(KeyCombo.keyCodeToSwiftUICharacter.keys)
        #expect(fromKeyCodeMap == fromCharacterMap)
    }

    // MARK: - HotkeyManager Lifecycle

    @Test @MainActor func hotkeyManager_initialState_isNotRegistered() {
        let manager = HotkeyManager()
        #expect(!manager.isRegistered)
    }

    @Test @MainActor func hotkeyManager_registerWithValidCombo_becomesRegistered() {
        let manager = HotkeyManager()
        manager.register(keyCombo: "⌥⇧W") { }
        #expect(manager.isRegistered)
    }

    @Test @MainActor func hotkeyManager_registerWithInvalidCombo_staysUnregistered() {
        let manager = HotkeyManager()
        manager.register(keyCombo: "") { }
        #expect(!manager.isRegistered)
    }

    @Test @MainActor func hotkeyManager_unregister_becomesUnregistered() {
        let manager = HotkeyManager()
        manager.register(keyCombo: "⌥⇧W") { }
        #expect(manager.isRegistered)

        manager.unregister()
        #expect(!manager.isRegistered)
    }

    @Test @MainActor func hotkeyManager_reRegister_updatesCombo() {
        let manager = HotkeyManager()
        manager.register(keyCombo: "⌥⇧W") { }
        #expect(manager.isRegistered)

        manager.register(keyCombo: "⌘⇧K") { }
        #expect(manager.isRegistered)
    }

    @Test @MainActor func hotkeyManager_enableDisable() {
        let manager = HotkeyManager()
        manager.register(keyCombo: "⌥⇧W") { }
        #expect(manager.isRegistered)

        manager.setEnabled(false)
        #expect(!manager.isRegistered)

        manager.setEnabled(true)
        #expect(manager.isRegistered)
    }

    @Test @MainActor func hotkeyManager_disableWithoutPriorRegistration_staysUnregistered() {
        let manager = HotkeyManager()
        manager.setEnabled(false)
        #expect(!manager.isRegistered)

        manager.setEnabled(true)
        #expect(!manager.isRegistered)
    }

}
