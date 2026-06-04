# Migrate keyboard shortcuts to sindresorhus/KeyboardShortcuts

- **Date:** 2026-06-03
- **Status:** Approved (design)
- **Topic:** Replace the entire hand-rolled keyboard-shortcut stack with the `sindresorhus/KeyboardShortcuts` library.

## Goal

Remove the custom Carbon-based hotkey implementation and the custom shortcut
recorder UI, and route all 16 keyboard shortcuts (1 global + 15 in-app) through
the `KeyboardShortcuts` library. This deletes a large amount of bespoke parsing,
key-mapping, and event-handling code and replaces it with a maintained,
sandbox-friendly dependency.

## Decisions (confirmed)

1. **Full replacement** — all shortcuts move to `KeyboardShortcuts`, not just the global one.
2. **No migration** — existing user customizations in `UserDefaults` (`shortcut.*`,
   `globalHotkeyKeyCombo`) are **reset to defaults**. Legacy keys are deleted on launch.
3. **Default shortcuts unchanged** — the in-app defaults keep their current values
   (⌘N, ⌘P, ⌫, etc.) and the global default stays ⌥⇧W.

## Key strategy: two separate mechanisms

`KeyboardShortcuts` is fundamentally a **global** shortcut library, so the two
shortcut classes must be wired differently:

| Class | Count | Mechanism | Why |
|-------|-------|-----------|-----|
| **Global hotkey** | 1 | `KeyboardShortcuts.Name` + `onKeyDown` + `Recorder(name:)` | Library registers and monitors the shortcut system-wide. |
| **In-app shortcuts** | 15 | `Shortcut?` stored in our own store + `Recorder(shortcut: $binding)` + `.keyboardShortcut(shortcut?.toSwiftUI)` | **Must not** register globally — otherwise ⌘C etc. would be intercepted in other apps. The Binding form records without registering a global hotkey. |

> **Critical constraint:** In-app shortcuts must use the Binding-based `Recorder`
> and `toSwiftUI`, never the `Name`/`onKeyDown` path. Using `Name` for in-app
> actions would leak them into a system-wide registration.

## Relevant library API (verified)

- Add via SwiftPM: `https://github.com/sindresorhus/KeyboardShortcuts` (min macOS 10.15; app targets 15+).
- `KeyboardShortcuts.Shortcut` conforms to `Hashable, Codable, Sendable` → can be persisted directly via `Codable` in `UserDefaults`.
- `Shortcut.toSwiftUI: KeyboardShortcut?` (macOS 11+) → feeds SwiftUI `.keyboardShortcut(_:)`.
- `Shortcut.nsMenuItemKeyEquivalent: String?` and `Shortcut.modifiers: NSEvent.ModifierFlags` → set `NSMenuItem.keyEquivalent` / `keyEquivalentModifierMask`.
- `KeyboardShortcuts.Recorder` has a `Name`-based form and a `Binding<Shortcut?>`-based form.
- `KeyboardShortcuts.onKeyDown(for:)` / `onKeyUp(for:)` register global handlers.
- `KeyboardShortcuts.disable(_:)` / `enable(_:)` toggle a registered name.

## Code to remove

| File | Reason |
|------|--------|
| `Services/HotkeyManager.swift` (incl. `KeyCombo`, `KeyMapping`) | Carbon `RegisterEventHotKey` wrapper, replaced by the library. |
| `ViewModels/HotkeyRecorderViewModel.swift` | Custom recording logic, replaced by `Recorder`. |
| `Views/HotkeyRecorderView.swift` | Custom recorder view, replaced by `Recorder`. |
| `Views/KeyRecordingField.swift` | `NSEvent` key-capture field, no longer needed. |
| `OhMyWorktreeTests/HotkeyManagerTests.swift` | Tests for deleted code. |
| `OhMyWorktreeTests/HotkeyRecorderViewModelTests.swift` | Tests for deleted code. |
| `ShortcutManager.migrateLegacyKeys` + all string-combo parsing | Reset approach makes parsing/migration obsolete. |

## Code to add / change

1. **`project.yml`** — add the `KeyboardShortcuts` SPM package to the app target; run `xcodegen generate`.
2. **`KeyboardShortcuts.Name` extension** (new, e.g. `Services/ShortcutNames.swift`) — define the global hotkey:
   `static let toggleMenuBarPopup = Self("toggleMenuBarPopup", initial: .init(.w, modifiers: [.option, .shift]))`.
3. **`Models/ShortcutAction.swift`** — remove the `globalHotkey` case (now a `Name`); keep the 15 in-app cases. Replace `defaultCombo: String` with `defaultShortcut: KeyboardShortcuts.Shortcut`. Drop `isGlobal`.
4. **`Services/ShortcutStore.swift`** (rename/slim of `ShortcutManager`) — in-app shortcuts only:
   - Persist `Shortcut?` per action as `Codable` in `UserDefaults`.
   - `shortcut(for:) -> Shortcut?`, `binding(for:) -> Binding<Shortcut?>`, `resetAllToDefaults()`.
   - In-app-vs-in-app conflict detection (preserve existing behavior).
   - Remains `@Observable @MainActor`.
5. **`AppDelegate.setupGlobalHotkey()`** — replace `HotkeyManager` with
   `KeyboardShortcuts.onKeyDown(for: .toggleMenuBarPopup) { … toggle … }`; the
   `globalHotkeyEnabled` toggle drives `KeyboardShortcuts.enable/disable`. Remove the `hotkeyManager` property.
6. **`Views/ContentView.swift` and `Views/WorktreeListView.swift`** — replace
   `shortcutManager.keyboardShortcut(for:)` with `store.shortcut(for:)?.toSwiftUI`.
7. **`AppDelegate+Menu.swift`** — for menu items that map to a `ShortcutAction`
   (e.g. New Worktree, Settings, Git Pull, Show in Finder, Copy Path), replace the
   hard-coded `keyEquivalent` with `store` lookups: set
   `item.keyEquivalent = shortcut.nsMenuItemKeyEquivalent ?? ""` and
   `item.keyEquivalentModifierMask = shortcut.modifiers`. Standard items not in
   `ShortcutAction` (e.g. Quit ⌘Q) keep their hard-coded equivalents.
8. **`Views/ShortcutsSettingsView.swift`** — global section uses
   `KeyboardShortcuts.Recorder("…", name: .toggleMenuBarPopup)` + enable toggle;
   in-app section uses `KeyboardShortcuts.Recorder(action.displayName, shortcut: store.binding(for: action))`; keep "Reset All to Defaults".
9. **Legacy cleanup** — on launch, delete the old `shortcut.*` and `globalHotkeyKeyCombo` `UserDefaults` keys once.

## Default shortcuts (unchanged)

Global (via `KeyboardShortcuts.Name`):

| Action | Default |
|--------|---------|
| Toggle Menu Bar Popup | ⌥⇧W |

In-app (via `ShortcutStore`, `ShortcutAction.defaultShortcut`):

| Action | Default | Action | Default |
|--------|---------|--------|---------|
| Open Settings | ⌘, | Open in iTerm | ⌘⇧I |
| Add Repository | ⌘⇧N | Open in Ghostty | ⌘⇧G |
| New Worktree | ⌘N | Open in VSCode | ⌘⇧V |
| Remove Worktree | ⌫ | Open in Cursor | ⌘⇧C |
| Force Remove Worktree | ⌘⌫ | Open in cmux | ⌘⇧M |
| Quick Remove Worktree | ⇧⌘⌫ | Refresh Worktrees | ⌘R |
| Git Pull | ⌘P | Show in Finder | ⌘O |
| Copy Path | ⌘C | | |

## Testing

- **Remove:** `HotkeyManagerTests`, `HotkeyRecorderViewModelTests`.
- **Keep / update:** `ShortcutActionTests` (assert `defaultShortcut` values), new
  `ShortcutStoreTests` (persist/read, conflict detection, reset-all).
- The `KeyboardShortcuts` library itself is not unit-tested by us.
- Per `CLAUDE.md`: run `swiftlint lint` and the test scheme before any commit.

## Verification (after implementation)

- Global hotkey toggles the menu bar popup from any app; enable/disable toggle works.
- In-app shortcuts fire **only when the app is focused** — confirm no leakage into other apps (e.g. ⌘C does not get hijacked globally).
- `NSMenu` items display the correct shortcut glyphs.
- `swiftlint lint` clean; test scheme green.

## Risks / notes

- `toSwiftUI` may map a few special keys differently from the old hand-rolled
  mapping — verify ⌫ / ⌘⌫ / ⇧⌘⌫ and the menu glyphs after building.
- `NSMenuItem` modifier-mask mapping must be exact.
- Keep the in-app vs in-app conflict detection that the old `ShortcutManager` had.

## Out of scope

- No new shortcuts or actions added.
- No change to what each action does — only how the shortcut is stored, recorded, registered, and displayed.
- No data migration of prior user customizations (intentional reset).
