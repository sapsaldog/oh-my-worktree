import SwiftUI

/// Central manager for all configurable keyboard shortcuts.
/// Reads/writes user customizations via UserDefaults and provides conflict detection.
@Observable
@MainActor
final class ShortcutManager {

    private(set) var version: UInt = 0

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

    /// Notifies observers that a shortcut-related setting has changed.
    /// Used by ShortcutsSettingsView when the global hotkey toggle changes.
    func notifySettingsChanged() {
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

        guard let character = KeyCombo.keyCodeToSwiftUICharacter[parsed.keyCode] else { return nil }
        let key = KeyEquivalent(character)

        var modifiers: SwiftUI.EventModifiers = []
        if parsed.modifiers.contains(.command) { modifiers.insert(.command) }
        if parsed.modifiers.contains(.option) { modifiers.insert(.option) }
        if parsed.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if parsed.modifiers.contains(.control) { modifiers.insert(.control) }

        return (key, modifiers)
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

}
