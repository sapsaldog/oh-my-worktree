import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// System-wide hotkey that toggles the menu bar popup window.
    static let toggleMenuBarPopup = Self(
        "toggleMenuBarPopup",
        default: .init(.w, modifiers: [.option, .shift])
    )
}

extension KeyboardShortcuts.Shortcut {
    /// Converts this shortcut to a SwiftUI `KeyboardShortcut`, or `nil` if the key
    /// has no SwiftUI representation. Used to apply in-app shortcuts via
    /// `.keyboardShortcut(_:)` without registering a global hotkey.
    @MainActor
    var toSwiftUIShortcut: SwiftUI.KeyboardShortcut? {
        guard
            let keyEquivalent = nsMenuItemKeyEquivalent,
            let character = keyEquivalent.first
        else {
            return nil
        }
        return SwiftUI.KeyboardShortcut(
            SwiftUI.KeyEquivalent(character),
            modifiers: modifiers.swiftUIEventModifiers
        )
    }
}

extension NSEvent.ModifierFlags {
    /// These AppKit modifier flags expressed as SwiftUI `EventModifiers`.
    var swiftUIEventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if contains(.command) { result.insert(.command) }
        if contains(.option) { result.insert(.option) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.control) { result.insert(.control) }
        if contains(.capsLock) { result.insert(.capsLock) }
        return result
    }
}
