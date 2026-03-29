import SwiftUI
import XCTest

@testable import OhMyWorktree

final class ShortcutManagerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var manager: ShortcutManager!

    @MainActor
    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ShortcutManagerTests")!
        defaults.removePersistentDomain(forName: "ShortcutManagerTests")
        manager = ShortcutManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ShortcutManagerTests")
        defaults = nil
        manager = nil
        super.tearDown()
    }

    // MARK: - Defaults and Storage

    @MainActor
    func testComboForAction_noCustomization_returnsDefault() {
        XCTAssertEqual(manager.combo(for: .openSettings), "⌘,")
        XCTAssertEqual(manager.combo(for: .globalHotkey), "⌥⇧W")
    }

    @MainActor
    func testSetCombo_persistsToUserDefaults() {
        manager.setCombo("⌘⇧X", for: .openSettings)
        XCTAssertEqual(
            defaults.string(forKey: ShortcutAction.openSettings.userDefaultsKey),
            "⌘⇧X"
        )
    }

    @MainActor
    func testSetCombo_updatesReturnedValue() {
        manager.setCombo("⌘⇧X", for: .openSettings)
        XCTAssertEqual(manager.combo(for: .openSettings), "⌘⇧X")
    }

    @MainActor
    func testResetToDefault_clearsSingleShortcut() {
        manager.setCombo("⌘⇧X", for: .openSettings)
        manager.resetToDefault(.openSettings)
        XCTAssertEqual(manager.combo(for: .openSettings), "⌘,")
        XCTAssertNil(defaults.string(forKey: ShortcutAction.openSettings.userDefaultsKey))
    }

    @MainActor
    func testResetAllToDefaults_clearsAllCustomizations() {
        manager.setCombo("⌘⇧X", for: .openSettings)
        manager.setCombo("⌘⇧Y", for: .addRepository)
        manager.resetAllToDefaults()
        XCTAssertEqual(manager.combo(for: .openSettings), "⌘,")
        XCTAssertEqual(manager.combo(for: .addRepository), "⌘⇧N")
    }

    // MARK: - Conflict Detection

    @MainActor
    func testConflict_detectsSameComboOnDifferentActions() {
        // addWorktree default is "⌘N", so assigning "⌘N" to refreshWorktrees should conflict
        manager.setCombo("⌘N", for: .refreshWorktrees)
        let conflict = manager.conflictingAction(for: "⌘N", excluding: .refreshWorktrees)
        XCTAssertEqual(conflict, .addWorktree)
    }

    @MainActor
    func testConflict_noConflictForUniqueCombo() {
        let conflict = manager.conflictingAction(for: "⌘⇧Z", excluding: .openSettings)
        XCTAssertNil(conflict)
    }

    @MainActor
    func testConflict_emptyCombo_neverConflicts() {
        let conflict = manager.conflictingAction(for: "", excluding: .openSettings)
        XCTAssertNil(conflict)
    }

    @MainActor
    func testConflict_globalVsInApp_areSeparateNamespaces() {
        // Global hotkey default is "⌥⇧W". Assigning same to in-app should NOT conflict.
        manager.setCombo("⌥⇧W", for: .openSettings)
        let conflict = manager.conflictingAction(for: "⌥⇧W", excluding: .openSettings)
        XCTAssertNil(conflict)
    }

    // MARK: - KeyboardShortcut Helper

    @MainActor
    func testKeyboardShortcutForAction_commandComma() {
        let shortcut = manager.keyboardShortcut(for: .openSettings)
        XCTAssertNotNil(shortcut)
        XCTAssertEqual(shortcut?.key, ",")
        XCTAssertEqual(shortcut?.modifiers, .command)
    }

    @MainActor
    func testKeyboardShortcutForAction_commandN() {
        let shortcut = manager.keyboardShortcut(for: .addWorktree)
        XCTAssertNotNil(shortcut)
        XCTAssertEqual(shortcut?.key, "n")
        XCTAssertEqual(shortcut?.modifiers, .command)
    }

    @MainActor
    func testKeyboardShortcutForAction_disabledReturnsNil() {
        manager.setCombo("", for: .openSettings)
        let shortcut = manager.keyboardShortcut(for: .openSettings)
        XCTAssertNil(shortcut)
    }

    // MARK: - KeyboardShortcut Helper (Delete Key Variants)

    @MainActor
    func testKeyboardShortcutForAction_deleteWithoutModifiers() {
        // removeWorktree default is "⌫" (delete with no modifiers)
        let shortcut = manager.keyboardShortcut(for: .removeWorktree)
        XCTAssertNotNil(shortcut, "Delete key without modifiers should produce a valid shortcut")
        XCTAssertEqual(shortcut?.key, KeyEquivalent.delete)
        XCTAssertEqual(shortcut?.modifiers, [])
    }

    @MainActor
    func testKeyboardShortcutForAction_commandDelete() {
        // forceRemoveWorktree default is "⌘⌫"
        let shortcut = manager.keyboardShortcut(for: .forceRemoveWorktree)
        XCTAssertNotNil(shortcut)
        XCTAssertEqual(shortcut?.key, KeyEquivalent.delete)
        XCTAssertEqual(shortcut?.modifiers, .command)
    }

    @MainActor
    func testKeyboardShortcutForAction_shiftCommandDelete() {
        // quickRemoveWorktree default is "⇧⌘⌫"
        let shortcut = manager.keyboardShortcut(for: .quickRemoveWorktree)
        XCTAssertNotNil(shortcut)
        XCTAssertEqual(shortcut?.key, KeyEquivalent.delete)
        XCTAssertEqual(shortcut?.modifiers, [.shift, .command])
    }

    // MARK: - Version Counter

    @MainActor
    func testSetCombo_incrementsVersion() {
        let before = manager.version
        manager.setCombo("⌘⇧X", for: .openSettings)
        XCTAssertGreaterThan(manager.version, before)
    }

    @MainActor
    func testResetToDefault_incrementsVersion() {
        manager.setCombo("⌘⇧X", for: .openSettings)
        let before = manager.version
        manager.resetToDefault(.openSettings)
        XCTAssertGreaterThan(manager.version, before)
    }

    // MARK: - KeyboardShortcut Coverage

    @MainActor
    func testKeyboardShortcut_allDefaultCombos_areConvertible() {
        // Every non-global action's default combo should produce a valid KeyboardShortcut.
        // This guards against KeyCombo.keyCodeMap and ShortcutManager.keyCodeToCharacter drifting apart.
        for action in ShortcutAction.allCases where !action.isGlobal {
            let shortcut = manager.keyboardShortcut(for: action)
            XCTAssertNotNil(
                shortcut,
                "\(action) default combo '\(action.defaultCombo)' failed to convert to KeyboardShortcut"
            )
        }
    }

    // MARK: - Migration

    @MainActor
    func testMigration_copiesLegacyGlobalHotkeyKeyCombo() {
        defaults.set("⌘⇧K", forKey: "globalHotkeyKeyCombo")
        ShortcutManager.migrateLegacyKeys(defaults: defaults)
        XCTAssertEqual(
            defaults.string(forKey: ShortcutAction.globalHotkey.userDefaultsKey),
            "⌘⇧K"
        )
        XCTAssertNil(defaults.string(forKey: "globalHotkeyKeyCombo"))
    }

    @MainActor
    func testMigration_doesNotOverrideExistingNewKey() {
        defaults.set("⌘⇧K", forKey: "globalHotkeyKeyCombo")
        defaults.set("⌃⌥B", forKey: ShortcutAction.globalHotkey.userDefaultsKey)
        ShortcutManager.migrateLegacyKeys(defaults: defaults)
        // Existing new key should not be overwritten
        XCTAssertEqual(
            defaults.string(forKey: ShortcutAction.globalHotkey.userDefaultsKey),
            "⌃⌥B"
        )
    }
}
