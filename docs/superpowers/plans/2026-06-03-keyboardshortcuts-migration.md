# KeyboardShortcuts Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-rolled Carbon-based keyboard-shortcut stack with `sindresorhus/KeyboardShortcuts`, routing the 1 global + 15 in-app shortcuts through the library.

**Architecture:** Two mechanisms. The global hotkey uses `KeyboardShortcuts.Name` + `onKeyDown` (library registers it system-wide). In-app shortcuts persist a `KeyboardShortcuts.Shortcut?` in a slim `ShortcutStore` and apply via `.keyboardShortcut(shortcut?.toSwiftUI)` (no global registration → no leakage). Migration is done incrementally so every task compiles; legacy keys are reset (not migrated).

**Tech Stack:** Swift (app target Swift 6, test target Swift 5.9), SwiftUI, AppKit, Swift Testing (`@Test`/`#expect`), XcodeGen, KeyboardShortcuts (SPM).

---

## Project-specific rules (from CLAUDE.md)

- **No auto-commit.** The user must explicitly approve commits. The `Commit` step in each task is a checkpoint — only run it when the user has approved committing.
- **Before every commit:** run `swiftlint lint` AND the test scheme; fix failures first.
- After editing `project.yml`, always run `xcodegen generate`.

## Standard commands

- Regenerate project: `xcodegen generate`
- Build: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
- Test: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`
- Lint: `swiftlint lint`

## File Structure

**Create:**
- `OhMyWorktree/Services/ShortcutNames.swift` — `KeyboardShortcuts.Name.toggleMenuBarPopup` (global).
- `OhMyWorktree/Services/ShortcutStore.swift` — in-app shortcut persistence (`Shortcut?` via Codable), bindings, conflict lookup, reset, legacy cleanup.
- `OhMyWorktreeTests/ShortcutStoreTests.swift` — tests for the store.

**Modify:**
- `project.yml` — add KeyboardShortcuts package + dependency.
- `OhMyWorktree/Models/ShortcutAction.swift` — add `defaultShortcut`; later drop `globalHotkey`/`defaultCombo`/`isGlobal`.
- `OhMyWorktree/AppDelegate.swift` — global hotkey via library; remove `hotkeyManager`; `shortcutManager` → `shortcutStore`.
- `OhMyWorktree/AppDelegate+Actions.swift` — remove `observeShortcutChanges`/`observeShortcutVersion`.
- `OhMyWorktree/AppDelegate+Menu.swift` — sync New Worktree + Settings key equivalents from store.
- `OhMyWorktree/OhMyWorktreeApp.swift` — `ShortcutStore` state, env injection, legacy cleanup, global handler registration.
- `OhMyWorktree/Views/ContentView.swift` — use `ShortcutStore` + `toSwiftUI`.
- `OhMyWorktree/Views/WorktreeListView.swift` — use `ShortcutStore` + `toSwiftUI`.
- `OhMyWorktree/Views/ShortcutsSettingsView.swift` — `KeyboardShortcuts.Recorder` (both forms) + conflict warning.
- `OhMyWorktreeTests/ShortcutActionTests.swift` — assert `defaultShortcut`.

**Delete (Task 11):**
- `OhMyWorktree/Services/HotkeyManager.swift` (incl. `KeyCombo`/`KeyMapping`)
- `OhMyWorktree/Services/ShortcutManager.swift`
- `OhMyWorktree/ViewModels/HotkeyRecorderViewModel.swift`
- `OhMyWorktree/Views/HotkeyRecorderView.swift`
- `OhMyWorktree/Views/KeyRecordingField.swift`
- `OhMyWorktreeTests/HotkeyManagerTests.swift`
- `OhMyWorktreeTests/HotkeyRecorderViewModelTests.swift`
- `OhMyWorktreeTests/ShortcutManagerTests.swift`

---

## Task 1: Add the KeyboardShortcuts SPM dependency

**Files:**
- Modify: `project.yml:9-12` (packages), `project.yml:26-27` (dependencies)

- [ ] **Step 1: Add the package**

In `project.yml`, under `packages:` (after the Sparkle entry), add:

```yaml
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.3.0"
```

- [ ] **Step 2: Add the dependency to the app target**

In `project.yml`, under `targets.OhMyWorktree.dependencies:`, add below `- package: Sparkle`:

```yaml
      - package: KeyboardShortcuts
```

- [ ] **Step 3: Regenerate and build**

Run: `xcodegen generate`
Then: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED, KeyboardShortcuts resolved in `Package.resolved`.

- [ ] **Step 4: Commit** (only if approved)

```bash
git add project.yml OhMyWorktree.xcodeproj
git commit -m "build: add KeyboardShortcuts SPM dependency"
```

---

## Task 2: Define the global hotkey Name

**Files:**
- Create: `OhMyWorktree/Services/ShortcutNames.swift`

- [ ] **Step 1: Create the Name extension**

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// System-wide hotkey that toggles the menu bar popup window.
    static let toggleMenuBarPopup = Self(
        "toggleMenuBarPopup",
        default: .init(.w, modifiers: [.option, .shift])
    )
}
```

> If the compiler rejects the `default:` label, this KeyboardShortcuts version uses `initial:` instead — switch the label and rebuild.

- [ ] **Step 2: Build**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED (the Name is defined but not yet used).

- [ ] **Step 3: Commit** (only if approved)

```bash
git add OhMyWorktree/Services/ShortcutNames.swift
git commit -m "feat: define global hotkey KeyboardShortcuts.Name"
```

---

## Task 3: Switch the global hotkey to the library (AppDelegate)

**Files:**
- Modify: `OhMyWorktree/AppDelegate.swift` (add import; remove `hotkeyManager`; rewrite `setupGlobalHotkey`; add `registerGlobalHotkeyHandler`)
- Modify: `OhMyWorktree/AppDelegate+Actions.swift` (remove `observeShortcutChanges`/`observeShortcutVersion`)

- [ ] **Step 1: Import the library**

At the top of `AppDelegate.swift`, add after `import AppKit`:

```swift
import KeyboardShortcuts
```

- [ ] **Step 2: Remove the HotkeyManager property**

Delete this line (`AppDelegate.swift:37`):

```swift
    let hotkeyManager = HotkeyManager()
```

- [ ] **Step 3: Register the global handler once on launch**

In `applicationDidFinishLaunching` (`AppDelegate.swift:47-54`), append inside the method (after `setupStatusItem()`):

```swift
        if !Self.isRunningTests {
            registerGlobalHotkeyHandler()
        }
```

- [ ] **Step 4: Replace `setupGlobalHotkey` and add the handler registration**

Replace the entire `setupGlobalHotkey()` method (`AppDelegate.swift:166-178`) with:

```swift
    /// Registers the global hotkey handler once. The library keeps tracking the
    /// shortcut even after the user changes it via the recorder.
    func registerGlobalHotkeyHandler() {
        KeyboardShortcuts.onKeyDown(for: .toggleMenuBarPopup) { [weak self] in
            self?.showOrCreateMainWindow()
        }
    }

    /// Enables or disables the global hotkey based on the persisted toggle.
    func setupGlobalHotkey() {
        let enabled = UserDefaults.standard.object(forKey: "globalHotkeyEnabled") as? Bool ?? true
        if enabled {
            KeyboardShortcuts.enable(.toggleMenuBarPopup)
        } else {
            KeyboardShortcuts.disable(.toggleMenuBarPopup)
        }
    }
```

- [ ] **Step 5: Remove the shortcut-version observation**

In `AppDelegate+Actions.swift`, delete the entire `// MARK: - Shortcut Manager Observation` extension (`AppDelegate+Actions.swift:160-179`), i.e. `observeShortcutChanges()` and `observeShortcutVersion()`.

> These existed only to re-register the Carbon hotkey when the combo changed. The library no longer needs it. `setupGlobalHotkey()` is still called from `OhMyWorktreeApp` (kept in Task 7) and on the enable/disable toggle (Task 9).

- [ ] **Step 6: Build**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD FAILED — `OhMyWorktreeApp.swift` still calls `appDelegate.observeShortcutChanges()`. That call is removed in Task 7; if you are running tasks strictly in order, temporarily comment out line `OhMyWorktreeApp.swift:63` (`appDelegate.observeShortcutChanges()`) to get a green build, then restore/remove it in Task 7. Otherwise proceed to Task 7 before building.

- [ ] **Step 7: Commit** (only if approved, after a green build)

```bash
git add OhMyWorktree/AppDelegate.swift OhMyWorktree/AppDelegate+Actions.swift OhMyWorktree/OhMyWorktreeApp.swift
git commit -m "feat: drive global hotkey through KeyboardShortcuts"
```

---

## Task 4: Add `defaultShortcut` to ShortcutAction (keep legacy members)

**Files:**
- Modify: `OhMyWorktree/Models/ShortcutAction.swift`
- Test: `OhMyWorktreeTests/ShortcutActionTests.swift`

- [ ] **Step 1: Write the failing test**

In `ShortcutActionTests.swift`, add (and add `import KeyboardShortcuts` at the top):

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`
Expected: FAIL — `value of type 'ShortcutAction' has no member 'defaultShortcut'`.

- [ ] **Step 3: Implement `defaultShortcut`**

In `ShortcutAction.swift`, add `import KeyboardShortcuts` at the top, and add this computed property (keep `defaultCombo`, `globalHotkey`, `isGlobal` for now):

```swift
    /// The default shortcut for this action (KeyboardShortcuts representation).
    var defaultShortcut: KeyboardShortcuts.Shortcut {
        switch self {
        case .globalHotkey: .init(.w, modifiers: [.option, .shift])
        case .openSettings: .init(.comma, modifiers: [.command])
        case .addRepository: .init(.n, modifiers: [.command, .shift])
        case .addWorktree: .init(.n, modifiers: [.command])
        case .removeWorktree: .init(.delete, modifiers: [])
        case .forceRemoveWorktree: .init(.delete, modifiers: [.command])
        case .quickRemoveWorktree: .init(.delete, modifiers: [.command, .shift])
        case .openITerm: .init(.i, modifiers: [.command, .shift])
        case .openGhostty: .init(.g, modifiers: [.command, .shift])
        case .openVSCode: .init(.v, modifiers: [.command, .shift])
        case .openCursor: .init(.c, modifiers: [.command, .shift])
        case .openCmux: .init(.m, modifiers: [.command, .shift])
        case .refreshWorktrees: .init(.r, modifiers: [.command])
        case .gitPull: .init(.p, modifiers: [.command])
        case .showInFinder: .init(.o, modifiers: [.command])
        case .copyPath: .init(.c, modifiers: [.command])
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 5: Commit** (only if approved)

```bash
git add OhMyWorktree/Models/ShortcutAction.swift OhMyWorktreeTests/ShortcutActionTests.swift
git commit -m "feat: add ShortcutAction.defaultShortcut"
```

---

## Task 5: Create ShortcutStore (in-app persistence)

**Files:**
- Create: `OhMyWorktree/Services/ShortcutStore.swift`
- Test: `OhMyWorktreeTests/ShortcutStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OhMyWorktreeTests/ShortcutStoreTests.swift`:

```swift
import KeyboardShortcuts
import Testing
@testable import OhMyWorktree

@MainActor
struct ShortcutStoreTests {

    private func makeStore() -> (ShortcutStore, UserDefaults) {
        let suiteName = "ShortcutStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (ShortcutStore(defaults: defaults), defaults)
    }

    @Test func shortcut_whenNeverSet_returnsDefault() {
        let (store, _) = makeStore()
        #expect(store.shortcut(for: .addWorktree) == .init(.n, modifiers: [.command]))
    }

    @Test func setShortcut_thenRead_returnsStoredValue() {
        let (store, _) = makeStore()
        let custom = KeyboardShortcuts.Shortcut(.t, modifiers: [.command])
        store.setShortcut(custom, for: .addWorktree)
        #expect(store.shortcut(for: .addWorktree) == custom)
    }

    @Test func setShortcut_nil_disablesShortcut() {
        let (store, _) = makeStore()
        store.setShortcut(nil, for: .addWorktree)
        #expect(store.shortcut(for: .addWorktree) == nil)
    }

    @Test func resetAllToDefaults_restoresDefaults() {
        let (store, _) = makeStore()
        store.setShortcut(.init(.t, modifiers: [.command]), for: .addWorktree)
        store.resetAllToDefaults()
        #expect(store.shortcut(for: .addWorktree) == .init(.n, modifiers: [.command]))
    }

    @Test func conflictingAction_detectsDuplicate() {
        let (store, _) = makeStore()
        let dup = KeyboardShortcuts.Shortcut(.p, modifiers: [.command]) // gitPull default
        let conflict = store.conflictingAction(for: dup, excluding: .copyPath)
        #expect(conflict == .gitPull)
    }

    @Test func conflictingAction_excludesSelf() {
        let (store, _) = makeStore()
        let gitPullDefault = KeyboardShortcuts.Shortcut(.p, modifiers: [.command])
        #expect(store.conflictingAction(for: gitPullDefault, excluding: .gitPull) == nil)
    }

    @Test func setShortcut_bumpsVersion() {
        let (store, _) = makeStore()
        let before = store.version
        store.setShortcut(.init(.t, modifiers: [.command]), for: .addWorktree)
        #expect(store.version > before)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`
Expected: FAIL — `cannot find 'ShortcutStore' in scope`.

- [ ] **Step 3: Implement ShortcutStore**

Create `OhMyWorktree/Services/ShortcutStore.swift`:

```swift
import KeyboardShortcuts
import SwiftUI

/// Persists user-customizable IN-APP keyboard shortcuts as `KeyboardShortcuts.Shortcut`
/// values in `UserDefaults` (Codable). The global hotkey is handled separately via
/// `KeyboardShortcuts.Name` and is NOT managed here.
@Observable
@MainActor
final class ShortcutStore {

    private(set) var version: UInt = 0
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Read / Write

    /// The current shortcut for an action: the stored custom value, or the default
    /// if the user has never changed it. Returns `nil` if explicitly cleared.
    func shortcut(for action: ShortcutAction) -> KeyboardShortcuts.Shortcut? {
        guard defaults.object(forKey: action.userDefaultsKey) != nil else {
            return action.defaultShortcut
        }
        guard
            let data = defaults.data(forKey: action.userDefaultsKey),
            let decoded = try? JSONDecoder().decode(KeyboardShortcuts.Shortcut?.self, from: data)
        else {
            return nil
        }
        return decoded
    }

    /// Persists a shortcut for an action. Pass `nil` to disable it.
    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?, for action: ShortcutAction) {
        let data = try? JSONEncoder().encode(shortcut)
        defaults.set(data, forKey: action.userDefaultsKey)
        version += 1
    }

    /// A two-way binding suitable for `KeyboardShortcuts.Recorder(_:shortcut:)`.
    func binding(for action: ShortcutAction) -> Binding<KeyboardShortcuts.Shortcut?> {
        Binding(
            get: { self.shortcut(for: action) },
            set: { self.setShortcut($0, for: action) }
        )
    }

    /// Restores all in-app shortcuts to their defaults.
    func resetAllToDefaults() {
        for action in ShortcutAction.allCases {
            defaults.removeObject(forKey: action.userDefaultsKey)
        }
        version += 1
    }

    // MARK: - Conflict Detection

    /// The first in-app action already using `shortcut`, excluding the given action.
    func conflictingAction(
        for shortcut: KeyboardShortcuts.Shortcut?,
        excluding: ShortcutAction
    ) -> ShortcutAction? {
        guard let shortcut else { return nil }
        return ShortcutAction.allCases.first { action in
            action != excluding && self.shortcut(for: action) == shortcut
        }
    }

    // MARK: - Legacy Cleanup

    /// Removes pre-migration UserDefaults keys (old string combos) so they are not
    /// misread by the new Codable store. Safe to call on every launch.
    static func cleanUpLegacyDefaults(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "globalHotkeyKeyCombo")
        defaults.removeObject(forKey: "shortcut.globalHotkey")
        for action in ShortcutAction.allCases where defaults.string(forKey: action.userDefaultsKey) != nil {
            defaults.removeObject(forKey: action.userDefaultsKey)
        }
    }
}
```

> Note: while `ShortcutAction.globalHotkey` still exists (until Task 11), `resetAllToDefaults`/`conflictingAction` iterate it harmlessly — it just isn't shown in the in-app settings list. After Task 11 it is gone from `allCases`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 5: Commit** (only if approved)

```bash
git add OhMyWorktree/Services/ShortcutStore.swift OhMyWorktreeTests/ShortcutStoreTests.swift
git commit -m "feat: add ShortcutStore for in-app shortcuts"
```

---

## Task 6: Wire ShortcutStore into the app (OhMyWorktreeApp + AppDelegate)

**Files:**
- Modify: `OhMyWorktree/AppDelegate.swift` (property rename)
- Modify: `OhMyWorktree/OhMyWorktreeApp.swift` (state, cleanup, injection, connect)

- [ ] **Step 1: Rename the AppDelegate property**

In `AppDelegate.swift`, replace (`AppDelegate.swift:36`):

```swift
    var shortcutManager: ShortcutManager?
```

with:

```swift
    var shortcutStore: ShortcutStore?
```

- [ ] **Step 2: Update OhMyWorktreeApp state and init**

In `OhMyWorktreeApp.swift`, replace `@State private var shortcutManager = ShortcutManager()` (line 9) with:

```swift
    @State private var shortcutStore = ShortcutStore()
```

Replace the `init()` body (`OhMyWorktreeApp.swift:11-13`):

```swift
    init() {
        ShortcutStore.cleanUpLegacyDefaults()
    }
```

- [ ] **Step 3: Update environment injection**

In `OhMyWorktreeApp.swift`, change `.environment(shortcutManager)` (line 24) to:

```swift
                .environment(shortcutStore)
```

- [ ] **Step 4: Update connectAppDelegate**

Replace `connectAppDelegate()` (`OhMyWorktreeApp.swift:57-66`) with:

```swift
    private func connectAppDelegate() {
        appDelegate.repoViewModel = repoViewModel
        appDelegate.worktreeViewModel = worktreeViewModel
        appDelegate.updaterManager = updaterManager
        if appDelegate.shortcutStore !== shortcutStore {
            appDelegate.shortcutStore = shortcutStore
            appDelegate.setupGlobalHotkey()
        }
    }
```

> `observeShortcutChanges()` is gone (removed in Task 3). `setupGlobalHotkey()` here applies the enable/disable state at startup.

- [ ] **Step 5: Build**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD FAILED — `ContentView`/`WorktreeListView`/`ShortcutsSettingsView` still reference `ShortcutManager`. Fixed in Tasks 7–9. (If running strictly in order, proceed to Task 7 before building.)

- [ ] **Step 6: Commit** (only if approved, after Tasks 7–9 produce a green build)

Deferred — commit together with Task 9 (see Task 9 Step 4).

---

## Task 7: Migrate ContentView to ShortcutStore

**Files:**
- Modify: `OhMyWorktree/Views/ContentView.swift`

- [ ] **Step 1: Swap the environment type**

In `ContentView.swift`, change line 6:

```swift
    @Environment(ShortcutStore.self) var shortcutStore
```

And update `shortcutButtons` (`ContentView.swift:63-69`) to pass the store:

```swift
    private var shortcutButtons: some View {
        ShortcutButtonsView(
            repoViewModel: repoViewModel,
            worktreeViewModel: worktreeViewModel,
            store: shortcutStore
        )
    }
```

- [ ] **Step 2: Update ShortcutButtonsView**

In `ContentView.swift`, change the `ShortcutButtonsView` property (line 102) from `var shortcutManager: ShortcutManager` to:

```swift
    var store: ShortcutStore
```

Change the observation line (line 106) to:

```swift
        let _ = store.version
```

Replace the `shortcutButton(for:perform:)` helper (`ContentView.swift:148-154`) with:

```swift
    @ViewBuilder
    private func shortcutButton(for action: ShortcutAction, perform: @escaping () -> Void) -> some View {
        Button(action.displayName, action: perform)
            .keyboardShortcut(store.shortcut(for: action)?.toSwiftUI)
    }
```

> `.keyboardShortcut(_:)` accepts an optional `KeyboardShortcut?` (macOS 12.3+); `nil` means no shortcut. These buttons are hidden triggers, so always rendering them is fine.

- [ ] **Step 3: Build**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD FAILED — `WorktreeListView`/`ShortcutsSettingsView` still reference `ShortcutManager`. Continue to Task 8.

---

## Task 8: Migrate WorktreeListView to ShortcutStore

**Files:**
- Modify: `OhMyWorktree/Views/WorktreeListView.swift`

- [ ] **Step 1: Swap the environment type**

In `WorktreeListView.swift`, change line 5:

```swift
    @Environment(ShortcutStore.self) var shortcutStore
```

- [ ] **Step 2: Update contextMenuButton**

Replace the `contextMenuButton(_:action:role:perform:)` helper (`WorktreeListView.swift:230-243`) with:

```swift
    @ViewBuilder
    private func contextMenuButton(
        _ title: String,
        action: ShortcutAction,
        role: ButtonRole? = nil,
        perform: @escaping () -> Void
    ) -> some View {
        Button(title, role: role, action: perform)
            .keyboardShortcut(shortcutStore.shortcut(for: action)?.toSwiftUI)
    }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD FAILED — `ShortcutsSettingsView` still references `ShortcutManager`/`HotkeyRecorderView`. Continue to Task 9.

---

## Task 9: Rebuild ShortcutsSettingsView with library recorders

**Files:**
- Modify: `OhMyWorktree/Views/ShortcutsSettingsView.swift`

- [ ] **Step 1: Replace the whole view**

Replace the entire contents of `ShortcutsSettingsView.swift` with:

```swift
import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    var store: ShortcutStore
    @AppStorage("globalHotkeyEnabled") private var globalHotkeyEnabled = true

    var body: some View {
        Form {
            Section("Global Hotkey") {
                Toggle("Enable global hotkey", isOn: $globalHotkeyEnabled)
                    .onChange(of: globalHotkeyEnabled) { _, enabled in
                        if enabled {
                            KeyboardShortcuts.enable(.toggleMenuBarPopup)
                        } else {
                            KeyboardShortcuts.disable(.toggleMenuBarPopup)
                        }
                    }

                KeyboardShortcuts.Recorder("Toggle Menu Bar Popup:", name: .toggleMenuBarPopup)

                Text("Press the global hotkey to toggle the menu bar popup from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("In-App Shortcuts") {
                ForEach(Self.inAppActions, id: \.self) { action in
                    inAppRecorder(for: action)
                }
            }

            Section {
                Button("Reset All to Defaults") {
                    store.resetAllToDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func inAppRecorder(for action: ShortcutAction) -> some View {
        // Re-read on store changes so the conflict warning updates live.
        let _ = store.version
        VStack(alignment: .leading, spacing: 2) {
            KeyboardShortcuts.Recorder(action.displayName, shortcut: store.binding(for: action))
            if let conflict = store.conflictingAction(for: store.shortcut(for: action), excluding: action) {
                Text("Conflicts with \"\(conflict.displayName)\"")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private static let inAppActions = ShortcutAction.allCases.filter { !$0.isGlobal }
}
```

> `inAppActions` filters out `.globalHotkey` via `isGlobal` (still present until Task 11). After Task 11 this filter is simplified to just `ShortcutAction.allCases`.

- [ ] **Step 2: Build**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED (legacy `HotkeyManager`/`ShortcutManager`/recorder files still exist but compile).

- [ ] **Step 3: Run all tests**

Run: `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`
Expected: legacy `ShortcutManagerTests`/`HotkeyManagerTests`/`HotkeyRecorderViewModelTests` still pass (deleted in Task 11); new tests pass.

- [ ] **Step 4: Commit Tasks 6–9** (only if approved)

```bash
git add OhMyWorktree/OhMyWorktree
git commit -m "feat: route in-app shortcuts through ShortcutStore + KeyboardShortcuts.Recorder"
```

---

## Task 10: Sync menu bar key equivalents from the store

**Files:**
- Modify: `OhMyWorktree/AppDelegate+Menu.swift`

- [ ] **Step 1: Add a helper to apply a store shortcut to a menu item**

In `AppDelegate+Menu.swift`, add this private helper inside the `extension AppDelegate { … }` that contains `addSystemMenuItems` (e.g. just above `addSystemMenuItems`):

```swift
    /// Applies the current in-app shortcut for `action` to a menu item.
    private func applyShortcut(_ action: ShortcutAction, to item: NSMenuItem) {
        if let shortcut = shortcutStore?.shortcut(for: action) {
            item.keyEquivalent = shortcut.nsMenuItemKeyEquivalent ?? ""
            item.keyEquivalentModifierMask = shortcut.modifiers
        } else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        }
    }
```

- [ ] **Step 2: Use it for New Worktree**

In `addSystemMenuItems`, replace the New Worktree item construction (`AppDelegate+Menu.swift:97-104`) with:

```swift
        let addItem = NSMenuItem(
            title: "+ New Worktree",
            action: #selector(newWorktreeClicked(_:)),
            keyEquivalent: ""
        )
        applyShortcut(.addWorktree, to: addItem)
        addItem.target = self
        addItem.isEnabled = repoViewModel?.selectedRepository != nil
        menu.addItem(addItem)
```

- [ ] **Step 3: Use it for Settings**

Replace the Settings item construction (`AppDelegate+Menu.swift:126-132`) with:

```swift
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(settingsClicked(_:)),
            keyEquivalent: ""
        )
        applyShortcut(.openSettings, to: settingsItem)
        settingsItem.target = self
        menu.addItem(settingsItem)
```

> Leave "Open Main Window" (`o`) and "Quit" (`q`) hard-coded — they have no `ShortcutAction`.

- [ ] **Step 4: Build, lint, test**

Run: `xcodebuild ... build` (expect SUCCEEDED), `swiftlint lint` (expect no violations), `xcodebuild ... test` (expect PASS for current tests).

- [ ] **Step 5: Commit** (only if approved)

```bash
git add OhMyWorktree/AppDelegate+Menu.swift
git commit -m "feat: sync menu bar shortcuts from ShortcutStore"
```

---

## Task 11: Delete the legacy implementation

**Files:**
- Delete: `HotkeyManager.swift`, `ShortcutManager.swift`, `HotkeyRecorderViewModel.swift`, `HotkeyRecorderView.swift`, `KeyRecordingField.swift`
- Delete tests: `HotkeyManagerTests.swift`, `HotkeyRecorderViewModelTests.swift`, `ShortcutManagerTests.swift`
- Modify: `OhMyWorktree/Models/ShortcutAction.swift`, `OhMyWorktree/Views/ShortcutsSettingsView.swift`, `OhMyWorktreeTests/ShortcutActionTests.swift`

- [ ] **Step 1: Delete the source and test files**

```bash
git rm OhMyWorktree/Services/HotkeyManager.swift \
       OhMyWorktree/Services/ShortcutManager.swift \
       OhMyWorktree/ViewModels/HotkeyRecorderViewModel.swift \
       OhMyWorktree/Views/HotkeyRecorderView.swift \
       OhMyWorktree/Views/KeyRecordingField.swift \
       OhMyWorktreeTests/HotkeyManagerTests.swift \
       OhMyWorktreeTests/HotkeyRecorderViewModelTests.swift \
       OhMyWorktreeTests/ShortcutManagerTests.swift
```

- [ ] **Step 2: Remove `globalHotkey`, `defaultCombo`, `isGlobal` from ShortcutAction**

In `ShortcutAction.swift`: delete the `case globalHotkey` (line 5), delete the entire `defaultCombo` computed property, delete the `globalHotkey` arms from `defaultShortcut` and `displayName`, and delete the `isGlobal` computed property. The enum now lists the 15 in-app cases only; `userDefaultsKey`, `displayName`, and `defaultShortcut` remain.

- [ ] **Step 3: Simplify the settings filter**

In `ShortcutsSettingsView.swift`, replace:

```swift
    private static let inAppActions = ShortcutAction.allCases.filter { !$0.isGlobal }
```

with:

```swift
    private static let inAppActions = ShortcutAction.allCases
```

- [ ] **Step 4: Fix ShortcutActionTests**

In `ShortcutActionTests.swift`, remove any assertions referencing `.globalHotkey`, `defaultCombo`, or `isGlobal` (e.g. the `defaultCombo`/`isGlobal` test cases and the `globalHotkey` row). Keep/adjust the `defaultShortcut` and `userDefaultsKey` tests for the 15 in-app actions.

- [ ] **Step 5: Regenerate, build, lint, test**

Run: `xcodegen generate`
Run: `xcodebuild ... build` → BUILD SUCCEEDED
Run: `swiftlint lint` → no violations
Run: `xcodebuild ... test` → all PASS

- [ ] **Step 6: Commit** (only if approved)

```bash
git add -A
git commit -m "refactor: remove legacy Carbon hotkey and custom recorder code"
```

---

## Task 12: Final verification (manual)

- [ ] **Step 1: Full green build + lint + tests**

Run all three: `xcodegen generate` (no-op if unchanged), `xcodebuild ... build`, `swiftlint lint`, `xcodebuild ... test`. All must succeed.

- [ ] **Step 2: Manual smoke test (run the app)**

Launch the app and verify:
- Global hotkey (⌥⇧W by default) toggles the menu bar popup from another app.
- Settings → Shortcuts: global recorder records a new combo; the "Enable global hotkey" toggle disables/enables it.
- In-app recorders record new combos; a duplicate shows the "Conflicts with …" warning.
- An in-app shortcut (e.g. ⌘C "Copy Path") works when the app window is focused and does NOT get hijacked in another app.
- Menu bar menu shows the correct New Worktree / Settings key equivalents (and they reflect a customized value).
- `removeWorktree` (⌫, no modifier) and `forceRemoveWorktree` (⌘⌫) behave as before.

- [ ] **Step 3: Note any deviations** and fix before declaring done.

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Full replacement (global + in-app) → Tasks 2,3,5,7,8,9. ✓
- No migration / reset defaults → Task 5 (`cleanUpLegacyDefaults`) + Task 6. ✓
- Defaults unchanged → Task 4 (`defaultShortcut`) + Task 4 test. ✓
- Global via Name + onKeyDown → Tasks 2,3. ✓
- In-app via Binding + toSwiftUI → Tasks 5,7,8,9. ✓
- Remove HotkeyManager/recorder/ShortcutManager + tests → Task 11. ✓
- NSMenuItem via nsMenuItemKeyEquivalent/modifiers → Task 10 (scoped to New Worktree + Settings, per plan-level decision). ✓
- In-app conflict detection preserved → Task 5 (`conflictingAction`) + Task 9 (warning UI). ✓
- swiftlint + tests before commit → noted in rules + Tasks 10,11,12. ✓

**Deviations from spec (intentional, documented above):**
- NSMenu/`.commands`: only New Worktree + Settings are synced (other hard-coded equivalents kept) — spec's "AppDelegate+Menu store lookups" narrowed to avoid scope creep and regressions.
- Conflict detection is a non-blocking warning (library Recorder cannot veto via a plain Binding), matching the old warning-level behavior.

**Placeholder scan:** none.

**Type consistency:** `ShortcutStore.shortcut(for:) -> KeyboardShortcuts.Shortcut?`, `.toSwiftUI -> KeyboardShortcut?`, `binding(for:) -> Binding<KeyboardShortcuts.Shortcut?>`, `conflictingAction(for:excluding:)` consistent across Tasks 5/7/8/9/10. Property renamed `shortcutManager` → `shortcutStore` consistently in AppDelegate (Task 6), ContentView (Task 7), WorktreeListView (Task 8), ShortcutsSettingsView (Task 9), AppDelegate+Menu (Task 10).
