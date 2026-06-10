# Copied Files Diff & Apply-to-Main Design

## Context

When a worktree is created, `WorktreeFileCopier` copies git-ignored local files
(`.env*`, local configs matched by `.worktreeinclude`) **from the repository root
(the main worktree) into the new worktree**. After creation those copies drift:
the worktree's `.env` gets edited while the repository's copy stays behind.

Today the detail pane's **Copied files** section (`CopiedFilesSection`) only lists
file *names* (`WorktreeDetail.copiedFiles: [String]`) with an inline expand/filter.
It cannot tell whether a copy still matches main, show what changed, or push a
change back.

This feature, prototyped in the Claude Design handoff bundle
(`oh-my-worktree/project/`, chat transcript `chats/chat6.md`), makes the copied
files **diff-aware** and adds a **searchable browser sheet** that drills into a
GitHub-style unified diff and can **apply a copy back to main**.

The prototype is HTML/CSS/JS. The job is to recreate its visual + interaction
output in this SwiftUI app, not to copy its structure. The authoritative prototype
sources are `data.jsx` (`diffLines`, `CF`, `fileStatus`), `WorktreeWindow.jsx`
(`CopiedFiles`, `PathLabel`), `Sheets.jsx` (`CopiedFilesSheet`, `DiffBody`,
`CopiedFileRow`), and `omw.css` (`.cf-*`, `.fpop-*`, `.files-pop`, `.dl-*`, `.pl`).

## Approved Decisions

Confirmed with the user before this spec:

1. **Scope:** build the full feature in one branch (diff-aware chips + searchable
   browser sheet + drill-in diff + Apply-to-main), test-first.
2. **Binary / non-text files:** detect non-UTF-8 content; compare by bytes for
   status (`identical` vs `modified`); show "Binary — no preview" instead of a
   line diff; still allow Copy/Apply to main.
3. **Presentation:** a centered modal **glass sheet** (the app's existing
   `modalOverlay` + `glassModal` + `.glassSheet()` pattern), matching the
   prototype's centered `.files-pop` card. Not an anchored popover.

Additional defaults (from the prototype, not separately asked):

- **"main" = the repository root path** (`repository.path`). Worktree files are
  compared against, and applied back to, `repository.path/<relativePath>`.
- **Apply direction is worktree → main, whole-file.** No line-level/hunk apply, no
  bidirectional (main → worktree) revert. The assistant offered both in chat6;
  the user did not take them. Out of scope here.
- **Apply touches only the on-disk local copy. Nothing is staged or committed to
  Git.** A confirmation dialog precedes every overwrite.

## Scope

In scope:

- New tested model + logic units: `CopiedFileStatus`, `DiffLine`, `CopiedFile`,
  `LineDiff` (LCS line diff), `CopiedPath` (path split helper).
- New tested service `CopiedFileDiffer`: build `[CopiedFile]` by comparing each
  copied path's worktree vs repository content; apply a file back to main.
- Change `WorktreeDetail.copiedFiles` from `[String]` to `[CopiedFile]`; populate
  it in `WorktreeListViewModel.loadDetail`.
- Rewrite `CopiedFilesSection` to be diff-aware (status header + status chips +
  "View all" affordance).
- New view `CopiedFilesBrowser` (one glass sheet, list ↔ diff drill-in) plus
  `CopiedFileRow`, `UnifiedDiffView`, `PathLabel` subviews.
- Apply confirmation dialog (native `.alert`, matching `WorktreeRemovalDialogs`)
  and a success toast.
- Thin `WorktreeListViewModel` glue: browser open/close + drilled-in file state,
  `applyCopiedFileToMain`, post-apply detail reload + toast.
- Wire the browser into `ContentView.modalOverlay`; pass open handlers down through
  `DetailPaneView` → `CopiedFilesSection`.
- Full unit tests for every new Models/Services unit; update `WorktreeDetailTests`.

Out of scope:

- Line-level / per-hunk apply; bidirectional revert (main → worktree).
- Any Git staging/commit/stash of applied changes.
- Diffing tracked files or the worktree's own `git diff` (already shown by
  "Changes vs. base").
- Watching files for live diff refresh; status is computed on detail (re)load.
- Reworking the detail pane beyond the Copied files section.

## Architecture

Coverage rule that drives the split (see
`2026-06-03-coverage-100-gate-design.md` and `coverage-exclude.txt`):
`OhMyWorktree/Views/**` is **excluded** from the 100% gate; view models are in the
flaky quarantine. Therefore **all behavior lives in `Models/` + `Services/`
(100% tested), all rendering lives in `Views/` (excluded).** No new untested logic
may live in a view or view-model body.

### Models (new, in `OhMyWorktree/Models/`, 100% tested)

```
enum CopiedFileStatus: Sendable, Equatable {
    case identical          // text, same bytes
    case modified           // text, differs (has line diff)
    case new                // present in worktree, absent in main
    case binaryIdentical    // non-UTF-8, same bytes
    case binaryModified     // non-UTF-8, differs

    var isChanged: Bool     // modified | new | binaryModified
    var isClickable: Bool   // anything with something to show/apply (not identical/binaryIdentical)
    var sortRank: Int       // changed(0) < new(1) < identical(2), for list/chip ordering
}

struct DiffLine: Sendable, Equatable, Identifiable {
    enum Kind: Sendable { case context, add, del }
    let kind: Kind
    let text: String
    let lineA: Int?         // line number on the main side (nil for adds)
    let lineB: Int?         // line number on the worktree side (nil for dels)
    var id: Int             // stable index assigned at build time
}

struct CopiedFile: Sendable, Equatable, Identifiable {
    let path: String        // repo-relative path
    let status: CopiedFileStatus
    let added: Int
    let removed: Int
    let isBinary: Bool
    let mainContent: String?      // nil when new or binary
    let worktreeContent: String?  // nil when binary
    var id: String { path }
    var lines: [DiffLine]   // built once; empty for identical/binary
}
```

`CopiedPath.split(_ path:) -> (dir: String, base: String)` — directory (incl.
trailing `/`) and filename; powers `PathLabel`'s truncate-dir/keep-filename layout.

### Diff algorithm (new, `OhMyWorktree/Models/LineDiff.swift`, 100% tested)

Port of `data.jsx#diffLines` — an LCS-table line diff:

- Split both sides on `"\n"`.
- One side empty → all adds / all dels.
- Otherwise fill the `(n+1)×(m+1)` LCS length table, then walk it: equal → context,
  prefer del when `dp[i+1][j] >= dp[i][j+1]`, else add; drain the tails.
- Return `[DiffLine]` with 1-based `lineA`/`lineB` assigned as in the prototype.

`added` / `removed` counts = number of `add` / `del` lines.

### Service (new, `OhMyWorktree/Services/CopiedFileDiffer.swift`, 100% tested)

```
final class CopiedFileDiffer: Sendable {
    func compare(relativePaths: [String],
                 worktreePath: String,
                 repositoryPath: String) -> [CopiedFile]
    func applyToMain(_ file: CopiedFile,
                     worktreePath: String,
                     repositoryPath: String) throws
}
```

`compare`:
- For each relative path, read `worktreePath/<p>` and `repositoryPath/<p>` as `Data`.
- Worktree data present, repo data absent → `.new` (added = worktree line count).
- Both present, bytes equal → `.identical` (or `.binaryIdentical` if non-UTF-8).
- Both present, bytes differ:
  - both decode as UTF-8 → `.modified` + `LineDiff` + counts.
  - either is non-UTF-8 → `.binaryModified`, `isBinary = true`, no lines.
- Worktree data absent → skip (the copied-files list comes from scanning the
  worktree, so this should not happen; defensively omit).
- Result sorted by `(status.sortRank, path)`.

`applyToMain` (whole-file, worktree → repo):
- Source = `worktreePath/<p>`, dest = `repositoryPath/<p>`.
- Create dest parent dir (`withIntermediateDirectories: true`).
- Write the worktree bytes to a temp file in the destination directory, then place
  it: `replaceItemAt(dest, withItemAt: temp)` when dest exists, else `moveItem`.
  This makes the overwrite atomic so a crash can't truncate main's copy.
- Throw on read/write failure; the VM surfaces it via the existing error alert.

Reads/writes use `FileManager` exactly like `WorktreeFileCopier`, and are tested
with temp directories (the `WorktreeFileCopierTests` pattern already reaches 100%).

### View model glue (`WorktreeListViewModel`, excluded; keep thin)

- `loadDetail` calls `differ.compare(...)` (off the main actor via
  `Task.detached`, like the existing `includedFiles` call) and assigns
  `detail.copiedFiles`.
- New state: `copiedBrowser: CopiedBrowserState?` (which worktree's files + the
  drilled-in file, or nil = closed); `pendingApply: CopiedFile?`;
  `copiedToast: String?`.
- `applyCopiedFileToMain(_:)`: call `differ.applyToMain(...)`, then reload detail
  (recompute statuses) and set the toast. All real work is in the tested service;
  the VM is glue.

### Views (new/changed, `OhMyWorktree/Views/**`, excluded)

- `CopiedFilesSection` (rewrite): one-line header
  `Copied files {N}` + `· {M} changed` (orange) + `.worktreeinclude`; status chips
  (sorted, cap 5) — modified = orange dot + `+N −N`, new = green dot + `new`,
  identical = `doc` glyph dimmed; `View all {N} files` when `N > 5`. Clicking a
  changed chip opens the browser straight to that file's diff; "View all" opens the
  list. Uses `FlowLayout` + `PathLabel`.
- `CopiedFilesBrowser` (new): the `.glassSheet()` content. Two modes:
  - **List:** title `Copied files {N} · {M} changed vs. main`; search field
    ("Filter files…") + `Changed only` toggle (accent when on); scrollable
    `CopiedFileRow`s; footer hint + `Done`.
  - **Diff (drill-in):** `‹ All files` back button, `comparing vs. main` /
    `new file — not in main`; `PathLabel` title; `UnifiedDiffView` (or the binary
    placeholder); footer hint "Updates main's local copy only — nothing is
    committed to Git." + `Apply to main` / `Copy to main`.
  - Esc: diff → list, list → close (in-view `onExitCommand`/keyboard handling).
- `CopiedFileRow`, `UnifiedDiffView` (line-numbered red/green rows from
  `[DiffLine]`; binary placeholder), `PathLabel` (truncate dir, keep filename,
  full path as `.help` tooltip).

### Presentation & wiring

- Add a `copiedBrowser` branch to `ContentView.modalOverlay`, wrapped in the
  existing `glassModal { CopiedFilesBrowser(...).glassSheet() }`.
- Apply confirmation: a `.alert` on `ContentView` driven by `pendingApply`
  (destructive "Apply to main" + Cancel), worded like `WorktreeRemovalDialogs`
  ("Overwrites main's local copy of <file>. This is not committed to Git.").
- Toast: a small transient overlay bound to `copiedToast`, auto-dismissing.
- `DetailPaneView` gains `onOpenCopiedDiff: (CopiedFile) -> Void` and
  `onBrowseCopied: () -> Void`, forwarded to `CopiedFilesSection`.

## Visual reference (from `omw.css`)

- Status colors: modified `--sys-orange`, new `--sys-green`, add line bg
  green@13%, del line bg red@12%; counts `+` green / `−` red.
  All map to existing `OMWColor.sysOrange/.sysGreen/.sysRed` and label tiers.
- Chips: dot 6px; `chip-modified` = orange@15% over fill-tertiary; `chip-new` =
  green@15%; `chip-same` opacity .48.
- Diff rows (`.dl`): grid `34px 36px 16px 1fr` (lineA · lineB · sign · code),
  mono, `white-space: pre-wrap`, max-height ~380.
- Sheet (`.files-pop`): width 520, glass fill + blur, radius `--r-2xl`,
  `sheet-in` entrance. Maps to `.glassSheet()` + `glassModal`.
- `PathLabel` (`.pl`): `.pl-dir` ellipsis-truncates, `.pl-base` never shrinks.

## Testing & Coverage

100% line coverage on every new non-view file (the gate excludes `Views/**`).

- `LineDiffTests`: identical, all-add (empty main / new), all-del (empty
  worktree), single-line change, interleaved add/del, trailing newline, multi-line
  blocks, line-number assignment, empty-vs-empty.
- `CopiedFileTests` / `CopiedFileStatusTests`: status derivation incl. `new`,
  `identical`, `modified`, binary variants; `isChanged`/`isClickable`/`sortRank`;
  `added`/`removed`; `CopiedPath.split` (no slash, nested, trailing slash, dotfile).
- `CopiedFileDifferTests` (temp dirs): new, identical, modified, binary identical,
  binary modified; sort order; missing-in-main; `applyToMain` creating dirs,
  overwriting an existing copy, copying a new file, and error on an unwritable
  dest. Assert main's bytes equal the worktree's after apply, and that re-`compare`
  reports `identical`.
- `WorktreeDetailTests`: updated for `[CopiedFile]`, including `.empty`.

Pre-commit (per CLAUDE.md): `swiftlint lint` and the test scheme must pass.

## Verification

- `swiftlint lint`
- `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests \
  -destination 'platform=macOS' test`
- `scripts/coverage.sh` (100% gate; no new entries in `coverage-exclude.txt`)
- Manual smoke: select `feature/*` worktree with copied files → modified chips show
  `+N −N`; open browser, search + `Changed only`, drill into a diff, Apply to main
  → confirm dialog → chip flips to identical + toast. New file shows `new` →
  `Copy to main`.

## Risks & Edge Cases

- **Large/binary files:** reads load whole files into memory. Copied files are
  small configs; acceptable. Binary path avoids line-diffing entirely.
- **File deleted in worktree:** cannot occur — the list is derived by scanning the
  worktree; defensively skipped in `compare`.
- **Apply atomicity:** write-to-temp-then-replace prevents a partial overwrite of
  main's copy.
- **Symlinks / permissions:** `applyToMain` surfaces `FileManager` errors through
  the existing error alert rather than failing silently.
- **Path display:** very long monorepo paths handled by `PathLabel` truncation +
  tooltip; no layout overflow (the prototype's original inline-expand bug).
```
