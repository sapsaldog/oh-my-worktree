import AppKit
import KeyboardShortcuts
import Testing

@testable import OhMyWorktree

@MainActor
struct ShortcutNamesTests {

    @Test func toSwiftUIShortcut_convertsRegularKey() {
        let shortcut = KeyboardShortcuts.Shortcut(.p, modifiers: [.command])
        let converted = shortcut.toSwiftUIShortcut
        #expect(converted != nil)
        #expect(converted?.modifiers.contains(.command) == true)
    }

    @Test func swiftUIEventModifiers_mapsEveryFlag() {
        let all: NSEvent.ModifierFlags = [.command, .option, .shift, .control, .capsLock]
        let result = all.swiftUIEventModifiers
        #expect(result.contains(.command))
        #expect(result.contains(.option))
        #expect(result.contains(.shift))
        #expect(result.contains(.control))
        #expect(result.contains(.capsLock))
    }

    @Test func swiftUIEventModifiers_emptyForNoFlags() {
        #expect(NSEvent.ModifierFlags([]).swiftUIEventModifiers.isEmpty)
    }

    @Test func toSwiftUIShortcut_nilForUnrepresentableKey() {
        // An invalid carbon key code maps to no key, so nsMenuItemKeyEquivalent
        // is nil and the conversion returns nil.
        let shortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: 0xFFFF)
        #expect(shortcut.toSwiftUIShortcut == nil)
    }
}
