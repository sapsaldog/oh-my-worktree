import XCTest

@testable import OhMyWorktree

final class ShortcutActionTests: XCTestCase {

    // MARK: - Enum Integrity

    func testAllCases_haveUniqueRawValues() {
        let rawValues = ShortcutAction.allCases.map(\.rawValue)
        XCTAssertEqual(rawValues.count, Set(rawValues).count, "Duplicate raw values found")
    }

    func testAllCases_haveNonEmptyDefaults() {
        for action in ShortcutAction.allCases {
            XCTAssertFalse(action.defaultCombo.isEmpty, "\(action) has empty default combo")
        }
    }

    func testAllCases_defaultsAreParseable() {
        for action in ShortcutAction.allCases {
            XCTAssertNotNil(
                KeyCombo.from(string: action.defaultCombo),
                "\(action) default combo '\(action.defaultCombo)' is not parseable"
            )
        }
    }

    func testAllCases_haveUniqueDefaults() {
        let defaults = ShortcutAction.allCases.map(\.defaultCombo)
        XCTAssertEqual(defaults.count, Set(defaults).count, "Duplicate default combos found")
    }

    // MARK: - Specific Defaults

    func testGlobalHotkeyDefault_isOptionShiftW() {
        XCTAssertEqual(ShortcutAction.globalHotkey.defaultCombo, "⌥⇧W")
    }

    func testOpenSettingsDefault_isCommandComma() {
        XCTAssertEqual(ShortcutAction.openSettings.defaultCombo, "⌘,")
    }

    func testAddRepositoryDefault_isCommandShiftN() {
        XCTAssertEqual(ShortcutAction.addRepository.defaultCombo, "⌘⇧N")
    }

    func testAddWorktreeDefault_isCommandN() {
        XCTAssertEqual(ShortcutAction.addWorktree.defaultCombo, "⌘N")
    }

    func testRemoveWorktreeDefault_isBackspace() {
        XCTAssertEqual(ShortcutAction.removeWorktree.defaultCombo, "⌫")
    }

    func testForceRemoveWorktreeDefault() {
        XCTAssertEqual(ShortcutAction.forceRemoveWorktree.defaultCombo, "⌘⌫")
    }

    func testQuickRemoveWorktreeDefault() {
        XCTAssertEqual(ShortcutAction.quickRemoveWorktree.defaultCombo, "⇧⌘⌫")
    }

    func testOpenITermDefault() {
        XCTAssertEqual(ShortcutAction.openITerm.defaultCombo, "⌘⇧I")
    }

    func testOpenGhosttyDefault() {
        XCTAssertEqual(ShortcutAction.openGhostty.defaultCombo, "⌘⇧G")
    }

    func testOpenVSCodeDefault() {
        XCTAssertEqual(ShortcutAction.openVSCode.defaultCombo, "⌘⇧V")
    }

    func testOpenCursorDefault() {
        XCTAssertEqual(ShortcutAction.openCursor.defaultCombo, "⌘⇧C")
    }

    func testOpenCmuxDefault() {
        XCTAssertEqual(ShortcutAction.openCmux.defaultCombo, "⌘⇧M")
    }

    func testRefreshWorktreesDefault() {
        XCTAssertEqual(ShortcutAction.refreshWorktrees.defaultCombo, "⌘R")
    }

    // MARK: - UserDefaults Key

    func testUserDefaultsKey_format() {
        XCTAssertEqual(ShortcutAction.openSettings.userDefaultsKey, "shortcut.openSettings")
        XCTAssertEqual(ShortcutAction.globalHotkey.userDefaultsKey, "shortcut.globalHotkey")
    }

    // MARK: - Global Flag

    func testIsGlobal_onlyGlobalHotkey() {
        XCTAssertTrue(ShortcutAction.globalHotkey.isGlobal)
        for action in ShortcutAction.allCases where action != .globalHotkey {
            XCTAssertFalse(action.isGlobal, "\(action) should not be global")
        }
    }

    // MARK: - Display Name

    func testAllCases_haveNonEmptyDisplayNames() {
        for action in ShortcutAction.allCases {
            XCTAssertFalse(action.displayName.isEmpty, "\(action) has empty display name")
        }
    }
}
