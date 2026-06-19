# Copied-file diff: external diff-tool hand-off

**Date:** 2026-06-18
**Status:** Approved design — ready for implementation plan
**Source of truth:** `Oh My Worktree.zip` Claude Design prototype (`data.jsx`, `WorktreeWindow.jsx`,
`Sheets.jsx`, `App.jsx`, `diff-concepts.jsx`)

## Summary

Replace the in-app inline diff for `.worktreeinclude` copied files with a hand-off to an external
diff/merge tool. Clicking a copied-file chip (detail pane) or row (the "View all" browser) opens that
file's `main`-copy ↔ `worktree`-copy pair in the user's chosen diff tool. The chosen tool is selected
from a picker that appears in three places and is remembered as a persisted default.

This is a **full replacement**: the in-app unified diff view and the "Apply to main" / "Copy to
worktree" actions are removed. Merging back to `main` becomes the user's job inside the external tool
(the design's stated direction — App.jsx: *"Hand a copied file off to the chosen external diff tool
(no in-app diff)."*).

## Motivation / what changed in the design

The prototype pivots the copied-file diff experience from in-app to external hand-off:

- **`data.jsx`** introduces `DIFF_TOOLS`: Araxis Merge, Kaleidoscope, Beyond Compare, VS Code,
  FileMerge — auto-detected, only installed ones launch.
- **`DiffToolMenu`** ("Open diffs in [tool ▾]") is added to the detail-pane *Copied files* header
  (`WorktreeWindow.jsx`), the *View all* browser popover header (`Sheets.jsx`), and **Settings →
  General** as a persisted "Diff tool" default (`Sheets.jsx`).
- **`App.jsx`** wires every copied-file click to `openInDiffTool(file)` with no in-app diff;
  the selection persists as `t.diffTool`.
- `diff-concepts.jsx` is an exploration board (concepts A–F); the realized app lands on the
  external hand-off + picker family (C/E/F).

## Current behavior (today)

- Chip/row click → in-app `UnifiedDiffView` with "Apply to main" / "Copy to worktree"
  (`CopiedFilesSection.swift`, `CopiedFilesBrowser.swift`, `UnifiedDiffView.swift`).
- `CopiedFileDiffer` computes the diff and performs `applyToMain` / `applyToWorktree`
  (`WorktreeListViewModel+CopiedFiles.swift`).
- No diff-tool concept exists anywhere: `AppSettings` has no field, `ExternalToolLauncher` knows only
  terminals/editors (iTerm, Ghostty, VSCode, Cursor, cmux).

## Target behavior

- The *Copied files* detail section and the *View all* browser each show a `DiffToolMenu` in their
  header. **Settings → General** gains a "Diff tool" row with the same menu (the persisted default).
- Clicking any copied-file chip/row (identical included) opens that file in the selected diff tool.
  Status, `+N −N` counts, sorting, search and "Changed only" are unchanged.
- The menu lists all five tools; not-installed tools are shown disabled with a "Not installed" hint
  (per the design's `DiffToolMenu`). The current selection shows a check.

## Architecture

Split pure logic (testable, must hit 100% line coverage) from impure execution (detection + process
launch, which lives in already coverage-excluded files).

### `DiffTool` — pure catalog (NEW, 100% covered)

A value type / enum describing the five tools. For each: stable `id`, display `name`, SF Symbol
name, the CLI/bundle used for detection, and **launch-argument assembly** for a `(mainPath,
worktreePath)` pair.

Launch matrix (left = `main` copy, right = `worktree` copy):

| Tool           | id            | command    | invocation                          |
|----------------|---------------|------------|-------------------------------------|
| Araxis Merge   | `araxis`      | `compare`  | `compare <main> <worktree>`         |
| Kaleidoscope   | `kaleidoscope`| `ksdiff`   | `ksdiff <main> <worktree>`          |
| Beyond Compare | `bcompare`    | `bcomp`    | `bcomp <main> <worktree>`           |
| VS Code        | `vscode`      | `code`     | `code --diff <main> <worktree>`     |
| FileMerge      | `filemerge`   | `opendiff` | `opendiff <main> <worktree>`        |

Pure, table-driven, and unit-tested: catalog contents, argument assembly, lookup-by-id, and the
"installed tools given an injected probe" filter all return deterministic values with no I/O.

### Detection + launch (NEW or extends `ExternalToolLauncher`; coverage-excluded)

`ExternalToolLauncher` (and `WorktreeListViewModel+ExternalTools.swift`) are already in
`coverage-exclude.txt`. The impure parts live here:

- **Detection probe:** resolve each tool's presence via app-bundle (`NSWorkspace`) and/or CLI path,
  reusing the existing `isXInstalled` / `findVSCodeCLI` patterns. Produces the installed-set the pure
  filter consumes.
- **Launch:** build the `Process` from `DiffTool`'s assembled args and run it (non-blocking),
  mirroring the existing terminal/editor launch code.

### Persistence — `@AppStorage("diffToolID")`

Match the existing settings pattern (`SettingsSheetContent`'s `GeneralTab` already uses
`@AppStorage("copyEnvFilesEnabled")`). Store the selected tool id in UserDefaults; read it directly
from the views that show the menu. **Do not** add a field to the `AppSettings` struct (it is
100%-coverage-gated and the SwiftUI settings layer doesn't use it). Default resolution: the persisted
id if still installed, else the first installed tool.

### `DiffToolMenu` — SwiftUI view (NEW; under `Views/**`, coverage-excluded)

Reusable picker rendering the design's `DiffToolMenu`: a button showing the current tool + chevron,
a popover/menu of all five tools with icon, name, disabled+"Not installed" for absent tools, and a
check on the current selection. Placed in:

1. `CopiedFilesSection` header — trailing slot, replacing the current `.worktreeinclude` mono label
   (the design header is `title + menu`, with no label).
2. `CopiedFilesBrowser` list header — same: the menu takes the trailing slot currently holding the
   `.worktreeinclude` label.
3. `SettingsSheetContent`'s General tab (`GeneralTab`) — a new "Diff tool" `SettingsRow` at the top.
   This is the **live** in-app settings sheet (opened via `isShowingSettings`). The `SettingsView` /
   `GeneralSettingsView` window is dead code (`showOrCreateSettingsWindow` is never called) — do not
   put live settings there.

### Wiring

- `ContentView.detailDiffTools` (or a ViewModel accessor) exposes the installed `DiffTool` set, like
  the existing `detailTools`.
- `DetailPaneView` / `CopiedFilesSection` gain the tool list + selected id + an
  `onOpenInDiffTool(CopiedFile)` callback. `CopiedFilesBrowser` likewise; its rows call the same
  callback instead of drilling into a diff.
- `WorktreeListViewModel+CopiedFiles` gains `openInDiffTool(_:for:)` which resolves the worktree path
  and the main repo path (same resolution `applyToMain` used) and calls the launcher. This file is
  coverage-excluded.

## Removal scope (full replacement)

Remove:

- `OhMyWorktree/Views/Detail/UnifiedDiffView.swift` (whole file).
- `CopiedFileDiffer.applyToMain` and `applyToWorktree`.
- `WorktreeListViewModel+CopiedFiles`: `openCopiedDiff`, `applyCopiedFileToMain`,
  `applyCopiedFileToWorktree` (and `pendingApply` state in the view model / `ContentView`).
- `CopiedFilesBrowser` diff drill-in: `diffView`, `diffHeader`, `applyButton`, `applyHint`,
  `diffSubtitle`, the `focusedPath` diff branch, and the `onApply` / `onApplyToWorktree` params.
- `ContentView` `onApply` / `onApplyToWorktree` wiring for the browser.

Keep (still needed):

- `CopiedFile` + `CopiedFile.classify` and `CopiedFileDiffer.compare` — chips/rows still show status
  and `+N −N` counts. Only the *rendering* of the diff and the *apply* actions go away.
- `CopiedFilesSection` chips, `CopiedFilesBrowser` list (search, "Changed only", sorting).
- The "View all" browser sheet itself (now a hand-off list, not a diff drill-in).

## Edge cases

- **`missing`** (in `main`, never copied to worktree): hand off the same way; the worktree-side path
  does not exist, so the tool shows a one-sided/new state. Verify per-tool during implementation and
  fall back gracefully (e.g. skip launch + brief toast) if a tool errors on a non-existent path.
- **`new`** (in worktree, not in `main`): symmetric — `main`-side path absent.
- **`identical`**: still opens in the diff tool (both copies are equal — the tool shows no
  differences); the chip/row is dimmed to mark it unchanged.
- **No diff tool installed:** every menu item is disabled and the menu button reads "No diff tool".
  Chips/rows stay buttons, but the hand-off is a no-op (nothing to launch), so the state is clear.
- **Persisted tool later uninstalled:** the *effective* tool = persisted-id-if-installed, else the
  first installed tool. The menu highlights the effective tool (not a disabled phantom), and launches
  use it. The stored id is left untouched so reinstalling restores the prior choice.

## Testing & coverage

- `Views/**`, `ExternalToolLauncher.swift`, `WorktreeListViewModel+ExternalTools.swift`, and
  `WorktreeListViewModel+CopiedFiles.swift` are already in `coverage-exclude.txt`, so the menu view,
  detection, and launch carry no line-coverage burden.
- The **pure** `DiffTool` catalog/arg/filter logic is **not** excluded and must reach 100% via unit
  tests (Swift Testing), driven with an injected detection probe so no real apps are needed.
- `CopiedFile`/`CopiedFileDiffer` remain 100% covered; removing `applyToMain`/`applyToWorktree` means
  deleting their tests too (no longer reachable code).
- Before any commit: `swiftlint lint` and the test scheme must pass, and `scripts/coverage.sh` must be
  green (per CLAUDE.md).

## Out of scope (YAGNI)

- "Custom command…" diff tool (explored in `diff-concepts.jsx`, dropped from the final `DIFF_TOOLS`;
  confirmed excluded for v1 — can be added later).
- In-app side-by-side / three-way / editable-result merge concepts (A, B, D).
- Per-hunk transfer, "apply to main" from within the app (now the external tool's responsibility).

## Acceptance criteria

1. A `DiffToolMenu` appears in the Copied files detail header, the View all browser header, and
   Settings → General; the selection persists across launches and defaults to the first installed
   tool.
2. Clicking any copied-file chip/row launches that file's `main`↔`worktree` pair in the selected
   tool; every file (identical included) is clickable, with identical ones visually dimmed.
3. Not-installed tools appear disabled with a "Not installed" hint; the current selection is checked.
4. The in-app unified diff view and the "Apply to main" / "Copy to worktree" actions no longer exist.
5. Status chips, counts, sorting, search, and "Changed only" behave as before.
6. `swiftlint`, tests, and `scripts/coverage.sh` (strict 100%) all pass.
