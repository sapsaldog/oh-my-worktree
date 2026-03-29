import SwiftUI
import Testing

@testable import OhMyWorktree

@MainActor
struct ShortcutManagerTests {

    let defaults: UserDefaults
    let manager: ShortcutManager

    init() throws {
        let suiteName = "ShortcutManagerTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        manager = ShortcutManager(defaults: defaults)
    }

    // MARK: - Defaults and Storage

    @Test func comboForAction_noCustomization_returnsDefault() {
        #expect(manager.combo(for: .openSettings) == "⌘,")
        #expect(manager.combo(for: .globalHotkey) == "⌥⇧W")
    }

    @Test func setCombo_persistsToUserDefaults() {
        manager.setCombo("⌘⇧X", for: .openSettings)
        #expect(
            defaults.string(forKey: ShortcutAction.openSettings.userDefaultsKey) == "⌘⇧X"
        )
    }

    @Test func setCombo_updatesReturnedValue() {
        manager.setCombo("⌘⇧X", for: .openSettings)
        #expect(manager.combo(for: .openSettings) == "⌘⇧X")
    }

    @Test func resetToDefault_clearsSingleShortcut() {
        manager.setCombo("⌘⇧X", for: .openSettings)
        manager.resetToDefault(.openSettings)
        #expect(manager.combo(for: .openSettings) == "⌘,")
        #expect(defaults.string(forKey: ShortcutAction.openSettings.userDefaultsKey) == nil)
    }

    @Test func resetAllToDefaults_clearsAllCustomizations() {
        manager.setCombo("⌘⇧X", for: .openSettings)
        manager.setCombo("⌘⇧Y", for: .addRepository)
        manager.resetAllToDefaults()
        #expect(manager.combo(for: .openSettings) == "⌘,")
        #expect(manager.combo(for: .addRepository) == "⌘⇧N")
    }

    // MARK: - Conflict Detection

    @Test func conflict_detectsSameComboOnDifferentActions() {
        manager.setCombo("⌘N", for: .refreshWorktrees)
        let conflict = manager.conflictingAction(for: "⌘N", excluding: .refreshWorktrees)
        #expect(conflict == .addWorktree)
    }

    @Test func conflict_noConflictForUniqueCombo() {
        let conflict = manager.conflictingAction(for: "⌘⇧Z", excluding: .openSettings)
        #expect(conflict == nil)
    }

    @Test func conflict_emptyCombo_neverConflicts() {
        let conflict = manager.conflictingAction(for: "", excluding: .openSettings)
        #expect(conflict == nil)
    }

    @Test func conflict_globalVsInApp_areSeparateNamespaces() {
        manager.setCombo("⌥⇧W", for: .openSettings)
        let conflict = manager.conflictingAction(for: "⌥⇧W", excluding: .openSettings)
        #expect(conflict == nil)
    }

    // MARK: - KeyboardShortcut Helper

    @Test func keyboardShortcutForAction_commandComma() throws {
        let shortcut = try #require(manager.keyboardShortcut(for: .openSettings))
        #expect(shortcut.key == ",")
        #expect(shortcut.modifiers == .command)
    }

    @Test func keyboardShortcutForAction_commandN() throws {
        let shortcut = try #require(manager.keyboardShortcut(for: .addWorktree))
        #expect(shortcut.key == "n")
        #expect(shortcut.modifiers == .command)
    }

    @Test func keyboardShortcutForAction_disabledReturnsNil() {
        manager.setCombo("", for: .openSettings)
        let shortcut = manager.keyboardShortcut(for: .openSettings)
        #expect(shortcut == nil)
    }

    // MARK: - KeyboardShortcut Helper (Delete Key Variants)

    @Test func keyboardShortcutForAction_deleteWithoutModifiers() throws {
        let shortcut = try #require(
            manager.keyboardShortcut(for: .removeWorktree),
            "Delete key without modifiers should produce a valid shortcut"
        )
        #expect(shortcut.key == KeyEquivalent.delete)
        #expect(shortcut.modifiers == [])
    }

    @Test func keyboardShortcutForAction_commandDelete() throws {
        let shortcut = try #require(manager.keyboardShortcut(for: .forceRemoveWorktree))
        #expect(shortcut.key == KeyEquivalent.delete)
        #expect(shortcut.modifiers == .command)
    }

    @Test func keyboardShortcutForAction_shiftCommandDelete() throws {
        let shortcut = try #require(manager.keyboardShortcut(for: .quickRemoveWorktree))
        #expect(shortcut.key == KeyEquivalent.delete)
        #expect(shortcut.modifiers == [.shift, .command])
    }

    // MARK: - Version Counter

    @Test func setCombo_incrementsVersion() {
        let before = manager.version
        manager.setCombo("⌘⇧X", for: .openSettings)
        #expect(manager.version > before)
    }

    @Test func resetToDefault_incrementsVersion() {
        manager.setCombo("⌘⇧X", for: .openSettings)
        let before = manager.version
        manager.resetToDefault(.openSettings)
        #expect(manager.version > before)
    }

    @Test func notifySettingsChanged_incrementsVersion() {
        let before = manager.version
        manager.notifySettingsChanged()
        #expect(manager.version > before)
    }

    // MARK: - KeyboardShortcut Coverage

    @Test(arguments: ShortcutAction.allCases.filter { !$0.isGlobal })
    func keyboardShortcut_allDefaultCombos_areConvertible(action: ShortcutAction) {
        let shortcut = manager.keyboardShortcut(for: action)
        #expect(
            shortcut != nil,
            "\(action) default combo '\(action.defaultCombo)' failed to convert to KeyboardShortcut"
        )
    }

    // MARK: - Migration

    @Test func migration_copiesLegacyGlobalHotkeyKeyCombo() {
        defaults.set("⌘⇧K", forKey: "globalHotkeyKeyCombo")
        ShortcutManager.migrateLegacyKeys(defaults: defaults)
        #expect(
            defaults.string(forKey: ShortcutAction.globalHotkey.userDefaultsKey) == "⌘⇧K"
        )
        #expect(defaults.string(forKey: "globalHotkeyKeyCombo") == nil)
    }

    @Test func migration_doesNotOverrideExistingNewKey() {
        defaults.set("⌘⇧K", forKey: "globalHotkeyKeyCombo")
        defaults.set("⌃⌥B", forKey: ShortcutAction.globalHotkey.userDefaultsKey)
        ShortcutManager.migrateLegacyKeys(defaults: defaults)
        #expect(
            defaults.string(forKey: ShortcutAction.globalHotkey.userDefaultsKey) == "⌃⌥B"
        )
    }
}
