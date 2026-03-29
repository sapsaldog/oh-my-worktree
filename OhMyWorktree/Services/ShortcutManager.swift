import Carbon.HIToolbox
import SwiftUI

/// Central manager for all configurable keyboard shortcuts.
/// Reads/writes user customizations via UserDefaults and provides conflict detection.
@MainActor
final class ShortcutManager: ObservableObject {

    @Published private(set) var version: UInt = 0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Read / Write

    /// Returns the current combo string for an action (user-customized or default).
    func combo(for action: ShortcutAction) -> String {
        defaults.string(forKey: action.userDefaultsKey) ?? action.defaultCombo
    }

    /// Persists a new combo for an action. Pass an empty string to disable.
    func setCombo(_ combo: String, for action: ShortcutAction) {
        defaults.set(combo, forKey: action.userDefaultsKey)
        version += 1
    }

    /// Removes the user customization, restoring the default combo.
    func resetToDefault(_ action: ShortcutAction) {
        defaults.removeObject(forKey: action.userDefaultsKey)
        version += 1
    }

    /// Restores all shortcuts to their defaults.
    func resetAllToDefaults() {
        for action in ShortcutAction.allCases {
            defaults.removeObject(forKey: action.userDefaultsKey)
        }
        version += 1
    }

    // MARK: - Conflict Detection

    /// Returns the first action that already uses `combo`, excluding the given action.
    /// Global and in-app shortcuts are in separate namespaces and do not conflict with each other.
    func conflictingAction(for combo: String, excluding: ShortcutAction) -> ShortcutAction? {
        guard !combo.isEmpty else { return nil }
        return ShortcutAction.allCases.first { action in
            action != excluding
            && action.isGlobal == excluding.isGlobal
            && self.combo(for: action) == combo
        }
    }

    // MARK: - SwiftUI KeyboardShortcut Helper

    /// Converts the current combo for an action into SwiftUI types.
    /// Returns nil if the combo is empty or unparseable.
    func keyboardShortcut(
        for action: ShortcutAction
    ) -> (key: KeyEquivalent, modifiers: SwiftUI.EventModifiers)? {
        let comboString = combo(for: action)
        guard !comboString.isEmpty, let parsed = KeyCombo.from(string: comboString) else { return nil }

        guard let character = Self.keyCodeToCharacter[parsed.keyCode] else { return nil }
        let key = KeyEquivalent(character)

        var modifiers: SwiftUI.EventModifiers = []
        if parsed.modifiers.contains(.command) { modifiers.insert(.command) }
        if parsed.modifiers.contains(.option) { modifiers.insert(.option) }
        if parsed.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if parsed.modifiers.contains(.control) { modifiers.insert(.control) }

        return (key, modifiers)
    }

    // MARK: - NSMenuItem Key Equivalent Helper

    /// Converts the current combo for an action into NSMenuItem-compatible key equivalent and modifiers.
    /// Returns nil if the combo is empty or unparseable.
    func menuItemKeyEquivalent(
        for action: ShortcutAction
    ) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        let comboString = combo(for: action)
        guard !comboString.isEmpty, let parsed = KeyCombo.from(string: comboString) else { return nil }

        guard let character = Self.keyCodeToMenuCharacter[parsed.keyCode] else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        if parsed.modifiers.contains(.command) { modifiers.insert(.command) }
        if parsed.modifiers.contains(.option) { modifiers.insert(.option) }
        if parsed.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if parsed.modifiers.contains(.control) { modifiers.insert(.control) }

        return (String(character), modifiers)
    }

    // MARK: - Migration

    /// Migrates legacy `globalHotkeyKeyCombo` key to the new `shortcut.globalHotkey` key.
    static func migrateLegacyKeys(defaults: UserDefaults = .standard) {
        let legacyKey = "globalHotkeyKeyCombo"
        guard let legacy = defaults.string(forKey: legacyKey) else { return }
        let newKey = ShortcutAction.globalHotkey.userDefaultsKey
        if defaults.string(forKey: newKey) == nil {
            defaults.set(legacy, forKey: newKey)
        }
        defaults.removeObject(forKey: legacyKey)
    }

    // MARK: - Key Code → Character Mapping

    private static let keyCodeToCharacter: [UInt16: Character] = [
        UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_B): "b", UInt16(kVK_ANSI_C): "c",
        UInt16(kVK_ANSI_D): "d", UInt16(kVK_ANSI_E): "e", UInt16(kVK_ANSI_F): "f",
        UInt16(kVK_ANSI_G): "g", UInt16(kVK_ANSI_H): "h", UInt16(kVK_ANSI_I): "i",
        UInt16(kVK_ANSI_J): "j", UInt16(kVK_ANSI_K): "k", UInt16(kVK_ANSI_L): "l",
        UInt16(kVK_ANSI_M): "m", UInt16(kVK_ANSI_N): "n", UInt16(kVK_ANSI_O): "o",
        UInt16(kVK_ANSI_P): "p", UInt16(kVK_ANSI_Q): "q", UInt16(kVK_ANSI_R): "r",
        UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_T): "t", UInt16(kVK_ANSI_U): "u",
        UInt16(kVK_ANSI_V): "v", UInt16(kVK_ANSI_W): "w", UInt16(kVK_ANSI_X): "x",
        UInt16(kVK_ANSI_Y): "y", UInt16(kVK_ANSI_Z): "z",
        UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".",
        UInt16(kVK_ANSI_Slash): "/",
        UInt16(kVK_Delete): Character(UnicodeScalar(8))  // matches KeyEquivalent.delete
    ]

    /// Character mapping for NSMenuItem key equivalents.
    /// Same as keyCodeToCharacter except backspace uses NSBackspaceCharacter (0x08).
    private static let keyCodeToMenuCharacter: [UInt16: Character] = {
        var map = keyCodeToCharacter
        map[UInt16(kVK_Delete)] = Character(UnicodeScalar(8))  // NSBackspaceCharacter
        return map
    }()
}
