# Menu Bar Worktree-Name Toggle — Design

- **Date:** 2026-06-07
- **Status:** Approved (pending spec review)
- **Branch:** `claude/musing-galileo-272ac5` (worktree)

## Summary

Add a Settings toggle that controls whether the menu bar status item shows only
its icon, or the icon followed by the current `repository/worktree` label. The
default is **icon only**.

## Background — Current Behavior

`AppDelegate.updateStatusItemTitle()` (`OhMyWorktree/AppDelegate.swift:200`)
**always** sets a text title next to the icon:

- repo + worktree selected → `" <repo>/<worktree>"`
- repo only → `" <repo>"`
- nothing → `" Oh My Worktree"`

There is no way to hide this text. The worktree label shown is
`worktree.customName ?? liveBranchName ?? worktree.displayName`.

### Settings UI reality

The repo has two settings surfaces, but only one is live:

- `SettingsSheetContent` (Liquid Glass sheet) — **the live UI**. Every entry
  point (app menu, shortcut, window button) sets
  `worktreeViewModel.isShowingSettings = true`, which presents this sheet.
- `SettingsView` (legacy `TabView`) + `GeneralSettingsView` — reached only via
  `AppDelegate.showOrCreateSettingsWindow()`, which **has no callers**. Dead code.

→ The new toggle goes into `SettingsSheetContent`'s `GeneralTab` only. The legacy
views are intentionally left untouched (YAGNI).

### Coverage constraint

`AppDelegate.swift` and `AppDelegate+*.swift` are on the coverage exclusion list
(`coverage-exclude.txt`). To keep the title logic testable and improve coverage,
the decision logic is extracted into a pure function (same strategy as
`DockPolicy`), which is **not** excluded and therefore requires 100% coverage.

## Requirements

1. A toggle in Settings → General: "Show worktree name in menu bar".
2. Default **off** → menu bar shows the icon only (empty title).
3. When **on** → behavior identical to today: `" <repo>/<worktree>"` /
   `" <repo>"` / `" Oh My Worktree"`.
4. Toggling applies immediately, no app restart.

## Design

### 1. Pure function — `OhMyWorktree/Services/MenuBarTitle.swift` (new)

```swift
enum MenuBarTitle {
    /// UserDefaults / @AppStorage key backing the toggle. Default: false (icon only).
    static let showWorktreeNameKey = "showWorktreeNameInMenuBar"

    /// Resolves the status-item title.
    /// - showWorktreeName: the user's toggle. When false, returns "" (icon only).
    /// - repoName: selected repository name, or nil.
    /// - worktreeName: resolved worktree label, or nil.
    static func text(showWorktreeName: Bool, repoName: String?, worktreeName: String?) -> String {
        guard showWorktreeName else { return "" }
        guard let repoName else { return " Oh My Worktree" }
        if let worktreeName { return " \(repoName)/\(worktreeName)" }
        return " \(repoName)"
    }
}
```

The leading space matches the existing format (icon uses `.imageLeading`, so the
space separates icon and text).

### 2. `AppDelegate` changes (`AppDelegate.swift`)

`updateStatusItemTitle()` delegates to the pure function:

```swift
func updateStatusItemTitle() {
    guard let button = statusItem?.button else { return }
    let showName = UserDefaults.standard.bool(forKey: MenuBarTitle.showWorktreeNameKey)
    let worktreeName = worktreeViewModel?.selectedWorktree.map { wt in
        wt.customName ?? liveBranchName ?? wt.displayName
    }
    button.title = MenuBarTitle.text(
        showWorktreeName: showName,
        repoName: repoViewModel?.selectedRepository?.name,
        worktreeName: worktreeName
    )
}
```

`setupStatusItem()` currently hardcodes `button.title = " Oh My Worktree"`.
Remove that hardcoded assignment and call `updateStatusItemTitle()` at the end of
`setupStatusItem()` instead. At setup time the view models are not injected yet
(`repoViewModel`/`worktreeViewModel` are nil), so the call resolves to `""` when
the toggle is off (default) or `" Oh My Worktree"` when it is on — the correct
initial state in both cases.

### 3. Immediate apply — Notification

Add to the existing `extension Notification.Name`:

```swift
static let menuBarTitleSettingChanged = Notification.Name("com.ohmyworktree.menuBarTitleSettingChanged")
```

`AppDelegate` subscribes (e.g. in `applicationDidFinishLaunching`, guarded by the
existing `!isRunningTests` path) and calls `updateStatusItemTitle()` on receipt.
This mirrors the proven `.showInDockSettingChanged` → `WindowObserver` pattern.

### 4. Settings UI — `SettingsSheetContent.swift`, `GeneralTab`

Add one `SettingsRow` after the "Show icon in Dock" row:

```swift
@AppStorage(MenuBarTitle.showWorktreeNameKey) private var showWorktreeName = false
...
settingsHairline()
SettingsRow(icon: "menubar.rectangle", title: "Show worktree name in menu bar",
            subtitle: "Display the repository and worktree next to the menu bar icon") {
    Toggle("Show worktree name in menu bar", isOn: $showWorktreeName).toggleStyle(.omwSwitch)
        .onChange(of: showWorktreeName) { _, _ in
            NotificationCenter.default.post(name: .menuBarTitleSettingChanged, object: nil)
        }
}
```

## Testing

New `OhMyWorktreeTests/MenuBarTitleTests.swift` covering every branch of
`MenuBarTitle.text`:

- `showWorktreeName = false` → `""` (independent of repo/worktree being set)
- `true`, repo `nil` → `" Oh My Worktree"`
- `true`, repo set, worktree `nil` → `" <repo>"`
- `true`, repo set, worktree set → `" <repo>/<worktree>"`

This yields 100% coverage for `MenuBarTitle.swift`. AppDelegate edits are within
the excluded files, so no additional gating; the pure function carries the logic.

## Out of Scope

- Legacy `SettingsView` / `GeneralSettingsView` (dead code) — not modified.
- Truncation / max-width handling of long labels — `NSStatusItem.variableLength`
  already handles layout; no change.
- Per-repository or per-worktree overrides.

## Verification

Per `CLAUDE.md`, before committing:

- `swiftlint lint`
- `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`
- `scripts/coverage.sh` (confirm `MenuBarTitle.swift` is 100%)
