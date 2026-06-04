import KeyboardShortcuts
import SwiftUI

/// Observable façade over `KeyboardShortcuts`' built-in storage for IN-APP shortcuts.
///
/// In-app shortcuts are stored solely by `KeyboardShortcuts` (keyed by `ShortcutAction.name`)
/// and are NOT registered as global hotkeys — no `onKeyDown`/`onKeyUp` handler is attached,
/// so the library never installs a system-wide Carbon hotkey for them. They apply only while
/// the app is focused, via `.keyboardShortcut(swiftUIShortcut(for:))`.
///
/// `version` bumps whenever a shortcut changes (the settings recorders call `noteChange()`,
/// and `resetInAppToDefaults()` bumps it directly) so SwiftUI views re-read their shortcuts live.
@Observable
@MainActor
final class ShortcutStore {

    private(set) var version: UInt = 0

    init() {
        // Register each in-app action's default shortcut in the library's storage
        // on first launch, so getShortcut(for:) returns the default until the user
        // customizes it. (KeyboardShortcuts.Name.init persists the default the first
        // time a name is created; doing it here keeps view bodies side-effect free.)
        for action in ShortcutAction.allCases where !action.isGlobal {
            _ = action.name
        }
    }

    /// Signals that a shortcut changed so observing views re-read.
    /// Called from the settings recorders' `onChange`.
    func noteChange() {
        version &+= 1
    }

    /// The SwiftUI shortcut currently bound to an action, or `nil` if unset/unrepresentable.
    func swiftUIShortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        KeyboardShortcuts.getShortcut(for: action.name)?.toSwiftUIShortcut
    }

    /// The first OTHER in-app action that currently shares `action`'s shortcut, if any.
    func conflictingAction(with action: ShortcutAction) -> ShortcutAction? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: action.name) else { return nil }
        return ShortcutAction.allCases.first {
            $0 != action && !$0.isGlobal && KeyboardShortcuts.getShortcut(for: $0.name) == shortcut
        }
    }

    /// Restores every in-app shortcut to its default.
    func resetInAppToDefaults() {
        let names = ShortcutAction.allCases.filter { !$0.isGlobal }.map(\.name)
        KeyboardShortcuts.reset(names)
        version &+= 1
    }
}
