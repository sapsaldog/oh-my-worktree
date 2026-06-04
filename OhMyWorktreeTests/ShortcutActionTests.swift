import KeyboardShortcuts
import Testing

@testable import OhMyWorktree

struct ShortcutActionTests {

    // MARK: - Enum Integrity

    @Test func allCases_haveUniqueRawValues() {
        let rawValues = ShortcutAction.allCases.map(\.rawValue)
        #expect(rawValues.count == Set(rawValues).count, "Duplicate raw values found")
    }

    @Test(arguments: ShortcutAction.allCases)
    func allCases_haveNonEmptyDefaults(action: ShortcutAction) {
        #expect(action.defaultCombo.isEmpty == false, "\(action) has empty default combo")
    }

    @Test(arguments: ShortcutAction.allCases)
    func allCases_defaultsAreParseable(action: ShortcutAction) {
        #expect(
            KeyCombo.from(string: action.defaultCombo) != nil,
            "\(action) default combo '\(action.defaultCombo)' is not parseable"
        )
    }

    @Test func allCases_haveUniqueDefaults() {
        let defaults = ShortcutAction.allCases.map(\.defaultCombo)
        #expect(defaults.count == Set(defaults).count, "Duplicate default combos found")
    }

    // MARK: - Specific Defaults (parameterized)

    @Test(arguments: [
        (ShortcutAction.globalHotkey, "⌥⇧W"),
        (.openSettings, "⌘,"),
        (.addRepository, "⌘⇧N"),
        (.addWorktree, "⌘N"),
        (.removeWorktree, "⌫"),
        (.forceRemoveWorktree, "⌘⌫"),
        (.quickRemoveWorktree, "⇧⌘⌫"),
        (.openITerm, "⌘⇧I"),
        (.openGhostty, "⌘⇧G"),
        (.openVSCode, "⌘⇧V"),
        (.openCursor, "⌘⇧C"),
        (.openCmux, "⌘⇧M"),
        (.refreshWorktrees, "⌘R"),
        (.gitPull, "⌘P"),
        (.showInFinder, "⌘O"),
        (.copyPath, "⌘C")
    ])
    func specificDefaults(action: ShortcutAction, expectedCombo: String) {
        #expect(action.defaultCombo == expectedCombo)
    }

    // MARK: - UserDefaults Key

    @Test func userDefaultsKey_format() {
        #expect(ShortcutAction.openSettings.userDefaultsKey == "shortcut.openSettings")
        #expect(ShortcutAction.globalHotkey.userDefaultsKey == "shortcut.globalHotkey")
    }

    // MARK: - Global Flag

    @Test func isGlobal_onlyGlobalHotkey() {
        #expect(ShortcutAction.globalHotkey.isGlobal)
        for action in ShortcutAction.allCases where action != .globalHotkey {
            #expect(action.isGlobal == false, "\(action) should not be global")
        }
    }

    // MARK: - Display Name

    @Test(arguments: ShortcutAction.allCases)
    func allCases_haveNonEmptyDisplayNames(action: ShortcutAction) {
        #expect(action.displayName.isEmpty == false, "\(action) has empty display name")
    }

    // MARK: - defaultShortcut (KeyboardShortcuts)

    @Test func defaultShortcut_inAppActions_matchCurrentDefaults() {
        #expect(ShortcutAction.addWorktree.defaultShortcut == .init(.n, modifiers: [.command]))
        #expect(ShortcutAction.addRepository.defaultShortcut == .init(.n, modifiers: [.command, .shift]))
        #expect(ShortcutAction.openSettings.defaultShortcut == .init(.comma, modifiers: [.command]))
        #expect(ShortcutAction.removeWorktree.defaultShortcut == .init(.delete, modifiers: []))
        #expect(ShortcutAction.forceRemoveWorktree.defaultShortcut == .init(.delete, modifiers: [.command]))
        #expect(ShortcutAction.quickRemoveWorktree.defaultShortcut == .init(.delete, modifiers: [.command, .shift]))
        #expect(ShortcutAction.gitPull.defaultShortcut == .init(.p, modifiers: [.command]))
        #expect(ShortcutAction.copyPath.defaultShortcut == .init(.c, modifiers: [.command]))
        #expect(ShortcutAction.showInFinder.defaultShortcut == .init(.o, modifiers: [.command]))
    }
}
