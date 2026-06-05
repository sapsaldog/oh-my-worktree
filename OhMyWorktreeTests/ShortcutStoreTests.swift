import KeyboardShortcuts
import Testing

@testable import OhMyWorktree

/// `ShortcutStore` is a façade over `KeyboardShortcuts`' global storage
/// (`UserDefaults.standard`), so these tests run serialized and reset the
/// in-app names they touch to avoid cross-test interference.
@Suite(.serialized)
@MainActor
struct ShortcutStoreTests {

    private func resetInApp() {
        for action in ShortcutAction.allCases where !action.isGlobal {
            KeyboardShortcuts.reset(action.name)
        }
    }

    @Test func init_registersInAppDefaults() {
        resetInApp()
        _ = ShortcutStore()
        #expect(KeyboardShortcuts.getShortcut(for: ShortcutAction.gitPull.name) == .init(.p, modifiers: [.command]))
        resetInApp()
    }

    @Test func noteChange_bumpsVersion() {
        let store = ShortcutStore()
        let before = store.version
        store.noteChange()
        #expect(store.version == before + 1)
    }

    @Test func swiftUIShortcut_nonNilForDefault() {
        resetInApp()
        let store = ShortcutStore()
        #expect(store.swiftUIShortcut(for: .gitPull) != nil)
        resetInApp()
    }

    @Test func swiftUIShortcut_nilWhenCleared() {
        let store = ShortcutStore()
        KeyboardShortcuts.setShortcut(nil, for: ShortcutAction.gitPull.name)
        #expect(store.swiftUIShortcut(for: .gitPull) == nil)
        resetInApp()
    }

    @Test func conflictingAction_nilWhenShortcutCleared() {
        let store = ShortcutStore()
        KeyboardShortcuts.setShortcut(nil, for: ShortcutAction.gitPull.name)
        #expect(store.conflictingAction(with: .gitPull) == nil)
        resetInApp()
    }

    @Test func conflictingAction_nilWhenUnique() {
        resetInApp()
        let store = ShortcutStore()
        #expect(store.conflictingAction(with: .addWorktree) == nil)
        resetInApp()
    }

    @Test func conflictingAction_detectsDuplicate() {
        resetInApp()
        let store = ShortcutStore()
        // Point copyPath at gitPull's default (⌘P) → conflict.
        KeyboardShortcuts.setShortcut(.init(.p, modifiers: [.command]), for: ShortcutAction.copyPath.name)
        #expect(store.conflictingAction(with: .copyPath) == .gitPull)
        resetInApp()
    }

    @Test func resetInAppToDefaults_restoresDefault() {
        let store = ShortcutStore()
        KeyboardShortcuts.setShortcut(.init(.t, modifiers: [.command]), for: ShortcutAction.gitPull.name)
        store.resetInAppToDefaults()
        #expect(KeyboardShortcuts.getShortcut(for: ShortcutAction.gitPull.name) == .init(.p, modifiers: [.command]))
        resetInApp()
    }

    @Test func menuItemKeyEquivalent_returnsKeyAndModifiers() {
        resetInApp()
        let store = ShortcutStore()
        let equivalent = store.menuItemKeyEquivalent(for: .gitPull)
        #expect(equivalent.key == "p")
        #expect(equivalent.modifiers.contains(.command))
        resetInApp()
    }

    @Test func menuItemKeyEquivalent_emptyWhenCleared() {
        let store = ShortcutStore()
        KeyboardShortcuts.setShortcut(nil, for: ShortcutAction.gitPull.name)
        let equivalent = store.menuItemKeyEquivalent(for: .gitPull)
        #expect(equivalent.key.isEmpty)
        #expect(equivalent.modifiers.isEmpty)
        resetInApp()
    }
}
