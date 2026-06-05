# Tahoe Liquid Glass Redesign — Main Window

**Date:** 2026-06-04
**Status:** Approved (pending spec review)
**Source design:** Claude Design handoff bundle (`Oh My Worktree.html`), recreated
from the prototype's CSS/JSX + screenshots + chat transcript.

## 1. Overview

Rebuild Oh My Worktree's **main window** as a macOS 26 "Tahoe" Liquid Glass app:
a 3-column window (repositories sidebar · worktree list · detail pane) under a
unified glass toolbar, with glass sheets, a right-click context menu, and toasts.
The app **stays a menu-bar utility** — only the main window's content is replaced.

The prototype renders a full simulated desktop (wallpaper, system menu bar, Dock)
purely to show glass refraction. That staging is **not** part of the app; real
macOS provides it.

### Decisions (confirmed with user)

| Question | Decision |
|---|---|
| Glass fidelity | **Require macOS 26 (Tahoe)**, use native Liquid Glass APIs. |
| Detail-pane data | **Full**: compute ahead/behind, diff stat, recent commits (with tests). |
| PR card review/checks | **Include**: extend the `gh` query + `PullRequestInfo` + tests. |
| Appearance | **User-selectable Auto / Light / Dark** (Settings → Appearance). Default **Auto** (follows system). |
| App nature | Keep menu-bar utility; rebuild the main window only. |
| Accent | **User-selectable**, 6 swatches incl. achromatic Graphite. Default **Purple `rgb(124,58,237)`**. |

> **v2 update (design bundle `Yjf38IabzQ-…`):** the only change from v1 is a new
> **Settings → Appearance** tab that promotes theme + accent from the prototype's
> dev-only Tweaks panel into real, persisted user preferences. See §8a.

### Non-goals

- No fake desktop/Dock/system-menubar (prototype staging only).
- No Tweaks dev panel. Its theme + accent controls are promoted to **Settings →
  Appearance** (§8a); its glass-intensity slider and layout toggle are dropped.
- The NSStatusItem menu stays a **native `NSMenu`** (the prototype's custom glass
  status dropdown is a prototype affordance, not standard for a menu-bar item).
  Its *contents* may be enriched later but its rendering is out of scope.
- "list-only" layout mode is dropped; the window is always 3-column (it resizes).

## 2. Design tokens

New Swift theme (under `Views/`, coverage-excluded). Values ported verbatim from
`colors_and_type.css`. SwiftUI `Color(.sRGB, …)` with explicit light/dark via the
environment color scheme (no hardcoded dark fork — define both and switch).

**System palette (both modes):** red `255,56,60` · orange `255,149,0` · yellow
`255,204,0` · green `52,199,89` · purple `175,82,222` · gray `142,142,147`
(others available but unused).

**Accent:** runtime value from the user's pick (see §8a). On-accent white. Palette
(dot order): Graphite `94,94,98` · Blue `0,122,255` · Purple `124,58,237` (default) ·
Green `52,199,89` · Orange `255,149,0` · Pink `255,45,85`.

**Light:** label primary `0,0,0/0.85`, secondary `/0.5`, tertiary `/0.26`,
quaternary `/0.1`; fill primary `/0.1`, secondary `/0.08`, tertiary `/0.05`;
separator `0,0,0/0.12`; bg-window `255,255,255`, bg-grouped `245,245,245`,
bg-raised `255,255,255`; sidebar `246,246,248/0.66`.

**Dark:** label primary `255,255,255/0.85`, secondary `/0.55`, tertiary `/0.25`,
quaternary `/0.1`; fills white `/0.1,/0.08,/0.05`; separator `255,255,255/0.14`;
bg-window `30,30,30`, bg-grouped `22,22,22`, bg-raised `44,44,46`; sidebar
`40,40,42/0.62`.

**Radii:** xs 4 · sm 6 · md 8 · lg 12 · xl 16 · 2xl 22 · pill 999.
**Fonts:** system (SF Pro) default; mono via `.system(size:weight:design:.monospaced)`.

## 3. Native Liquid Glass usage

In the prototype, glass is applied to **exactly six chrome surfaces** — everything
*inside* them (buttons, fields, rows, cards) is solid material. Match this exactly;
do not over-apply glass.

**Glass surfaces** → `.glassEffect(.regular, in: <shape>)`, co-located ones wrapped
in a `GlassEffectContainer`:
1. Unified toolbar (`.omw-toolbar`)
2. Sidebar (`.omw-sidebar`) — translucent vibrant panel
3. Detail pinned action bar (`.dt-actionbar`)
4. Sheets (`.sheet`)
5. Toast (`.toast`)
6. Context menu (`.ctx-menu`)

**NOT glass — solid control chips** (`--control-bg` / solid accent + `shadow-control`):
- All `.tb-round` toolbar buttons **including the accent ＋** (solid accent circle,
  *not* glass), the search field, GitHub/refresh/settings.
- `.ab-btn` action-bar buttons (incl. the primary labeled pill) and `.tool-btn`.

**Solid panes/cards:** list column = `bg-window` (scrolls under the glass toolbar
so the glass has something to refract); detail pane = `bg-grouped`; cards/meta =
`bg-raised`; rows = transparent over their pane, accent fill when selected.

**Dropped from the prototype:** `.omw-tools` footer (list-only mode) and `.popover`
repo dropdown (removed) — both were glass but are not rendered. The `.menubar`,
`.dock`, and `.mbmenu` glass belong to prototype staging, not the app.

## 4. Window & toolbar

**Window** (`AppDelegate+Window.swift`): `styleMask` adds `.fullSizeContentView`;
`titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, keep native
traffic lights. Default content size **1180×740**; min **860×520**.

**Toolbar** (`GlassToolbar`): height **52**, h-padding **14**, gap **10**, bottom
hairline. Left→right: traffic-light clearance (~78pt leading inset) → window title
`● <repo>` (accent dot 7pt + repo name, 13 semibold, secondary) → flexible spring →
search field (**230** wide, pill, leading magnifier) → GitHub-import → refresh →
settings → ＋(accent). Round buttons are **30×30** circles. Refresh icon spins
while loading. Search filters the list live.

## 5. Sidebar (220px)

`RepositorySidebar`, width **220**, glass sidebar fill, trailing hairline, padding
`6/8/8`. Header `REPOSITORIES` (11 bold, uppercase, tertiary, `+0.03em`) + ＋ add.
Repo rows: height **32**, gap **9**, padding `0 10`, radius **8** — folder-git icon
(accent) · name (13 medium, ellipsis) · count (11, tertiary). Selected → accent
fill, white text/icon/count. Footer (top hairline): `Settings`, `Check for Updates`
rows (28 tall, 12 medium, secondary).

## 6. List column + row

`WorktreeListColumn` (flex, `bg-window`). Head: padding `12/16/6`, `Worktrees`
(15 bold) + counter (12, tertiary): `"N worktrees"`, or `"M of N match"` while the
search field is non-empty. Empty/filtered-empty states per prototype.

`WorktreeRow`: gap **11**, padding `9 12`, radius **8**. Selected → accent fill,
all text/icons white; status dot gets a white ring.
- **Dot** (9pt): root/active green · locked orange · detached yellow · bare gray.
- **Line 1:** name (13 semibold, ellipsis) + badges: PR badge, Draft, locked,
  detached, `main` (root).
- **Line 2:** folder (folder icon 11 + name, 11) · `·` · commit hash (mono 11) ·
  `·` · `↑ahead` `↓behind` (mono 10, shown only when nonzero).
- **Right:** job indicator (spinner / ✓ green / ✗ red) **or** relative time (11).

**Badges** (`Badge`/`PrBadge`): height **16**, padding `0 6`, pill, 10 semibold.
pr-open green-tint · pr-merged purple-tint · pr-closed red-tint · draft fill ·
locked orange-tint · detached yellow-tint · main/gray fill. PR icon by state
(arrow / merge / closed), 11pt.

## 7. Detail pane (360px)

`DetailPane`, width **360**, `bg-grouped`, leading hairline. Vertical split:
scroll area + **pinned glass action bar**.

- **Empty:** centered git-branch (40, stroke 1.5) + "No worktree selected" + hint.
- **Hero** (`18/18/14`, bottom hairline): dot (11) + name (17 bold, wrap) + sub
  (folder icon 12 + folder · commit mono). Badges row: status label (gray badge),
  PR badge, Draft, locked.
- **Meta grid** (2×2, 1px gaps over separator, radius 8, cells `bg-raised`,
  padding `9/11`): Branch (mono), Commit (mono), Ahead/Behind (`↑n ↓n`),
  Last activity. Wrapped in `14/18` padding.
- **PR card** (if PR): header `Pull Request`. Card (`bg-raised`, radius 8, inset
  border, padding 12): `#num` (state color, mono bold) + PR badge + Draft +
  external-link (trailing); title (13 semibold); meta row: `by @author`,
  review summary, `checks <status>` (green when passing, orange otherwise).
  Whole card opens the PR URL.
- **Diff stat** (if files>0): header `Changes vs. base`. `+added`(green)
  `−removed`(red) mono · proportional bar (7 tall: green add seg + red rem seg) ·
  `N files`.
- **Copied files** (if any): header `Copied files .worktreeinclude`. Chips
  (mono 11, file icon, fill-tertiary, pill, 22 tall).
- **Recent commits:** header `Recent commits`. Rows: hash (accent mono) + message
  (12 medium) + `author · when` (10 tertiary); hairline between rows.
- **Action bar** (`dt-actionbar`, glass, padding `11/16`): `Open in` label +
  tools (trailing). First installed tool = accent labeled pill (icon + name);
  the rest = **32×32** icon-only glass buttons with hover tooltip. All disabled
  when the worktree is detached.

## 8. Sheets, context menu, toast

Glass sheets (radius **22**), sheet-in animation, scrim. Reuse `mac-*` control
styling (push button, pill, primary, switch, segmented, field, search).

- **Create Worktree** (480): name field + shuffle (random name from
  `RandomNameGenerator`, regenerates), base-branch segmented (main / develop /
  current HEAD), `.worktreeinclude` copy toggle. Cancel / Create.
- **Import PR** (520): Open/All segmented, search, PR rows (git-pr icon + title +
  Draft + `#num branch @author updated`). Cancel / Import. (Restyle existing
  `ImportPRView`.)
- **Settings** (tabbed General / Shortcuts / Updates). (Restyle existing
  `SettingsView` family.)
- **Context menu** (right-click row): Rename · Open in <tools> · Open PR #n (if
  PR) · Git Pull · Show in Finder · Copy Path · Remove / Quick Remove (danger,
  hidden for root). Native SwiftUI `.contextMenu` where it suffices.
- **Toast:** bottom-center glass pill (icon + message), auto-dismiss ~2.2s.

## 8a. Appearance & accent preferences (v2)

New **Settings → Appearance** tab, inserted between General and Shortcuts
(final tab order: General · Appearance · Shortcuts · Updates). Two rows in a
grouped section + a status caption:

- **Appearance row** — `contrast` icon, title "Appearance". Segmented control
  (`seg-appearance`) with three icon buttons: **Auto** (`sun-moon`), **Light**
  (`sun`), **Dark** (`moon`). Subtitle: in Auto →
  `Auto — follows your Mac (now Dark|Light)`; else `Light or dark window chrome`.
- **Accent row** — `palette` icon, title "Accent color", subtitle
  "Tints selection, switches, and focus". A row of six **22pt** accent dots
  (Graphite, Blue, Purple, Green, Orange, Pink) with a check on the selected one;
  selected dot gets a 2px `bg-raised` gap ring + 4px accent outer ring.
- **Caption** — `"{AccentName} · {Auto|Dark|Light}"`.

**Models (new, tested):**
- `AppearanceMode: String { auto, light, dark }` → `nsAppearance` mapping
  (auto → `nil` (follow system), light → `.aqua`, dark → `.darkAqua`) + display.
- `AccentChoice` — the six named accents → RGB + `Color`/`NSColor`; default
  `.purple`; lookup by raw name; stable ordered list for the dots.

**Persistence:** `@AppStorage` keys `appearanceMode` (default `auto`) and
`accentColorName` (default `Purple`) — consistent with `GeneralSettingsView`'s
existing `@AppStorage` usage.

**Application:**
- *Appearance* — AppDelegate (and the SwiftUI root) set `NSApp.appearance` /
  the main window's `appearance` from the pref: `nil` for Auto (system),
  `.aqua` / `.darkAqua` otherwise. Auto re-follows the system live (KVO on
  `effectiveAppearance` / `@Environment(\.colorScheme)`).
- *Accent* — the chosen `Color` is applied via `.tint(accent)` on the window root
  and read by the custom token layer (selection fill, switches, focus ring, ＋
  button, PR card hover border, commit hash, etc.). Views read it from an
  environment value seeded by the `@AppStorage` pref so changes apply instantly.

## 9. Backend: git detail (new, fully tested)

All via the existing `GitCommandExecuting` seam (mock = `MockGitExecutor`).
New file `Services/WorktreeManager+Detail.swift` (or `WorktreeDetailService`).

- **Ahead/behind** — `git rev-list --left-right --count @{upstream}...HEAD` in the
  worktree dir. Parse `"<behind>\t<ahead>"`. No upstream (exit ≠ 0 / stderr "no
  upstream") → `nil` (UI hides the figure). Model `AheadBehind { ahead, behind }`.
- **Diff stat vs base** — base = `git merge-base HEAD <defaultBranch>` (default
  branch from `origin/HEAD`, fallback `main`/`master`). Then
  `git diff --numstat <base>...HEAD`; sum added/removed; files = line count.
  Binary files (`-\t-`) count as files, 0 lines. Model
  `DiffStat { added, removed, files }`.
- **Recent commits** — `git log -n 5 --format=%h%x1f%s%x1f%an%x1f%ct` (unit
  separator `\x1f`, no quoting headaches). Parse to
  `Commit { hash, message, author, date }`; `when` = `relativeTimeString`.
- Aggregate `WorktreeDetail { aheadBehind?, diff, commits }`.

**Errors:** queries are best-effort; any failure yields the empty/nil shape and is
logged (`AppLog.debug`) — the detail pane degrades gracefully, never errors.

## 10. Backend: PR reviews + checks (new, tested)

- Extend `PullRequestInfo` with `reviewDecision: ReviewDecision?`
  (`approved/changesRequested/reviewRequired/none`) and `checkStatus: CheckStatus?`
  (`passing/failing/pending/none`).
- Extend both `gh pr list --json` arg lists with `reviewDecision,statusCheckRollup`.
- Parse `statusCheckRollup` (array of check runs/statuses) → reduce to
  passing (all success/neutral/skipped) · failing (any failure/error) · pending
  (any in-progress/queued/pending). Empty → `none`.
- Map `reviewDecision` to a human summary for the card (e.g. `APPROVED` →
  "approved", `CHANGES_REQUESTED` → "changes requested", else "review required" /
  "no reviews").
- Update `MockPRGitExecutor` fixtures + tests for the new fields (passing,
  failing, pending, empty, missing).

## 11. View-model changes (tested where logic added)

- `WorktreeListViewModel`: add `searchText: String` + `filteredWorktrees` computed
  (name/folder/branch contains, case-insensitive) for the toolbar search + counter.
- Detail loading: a `selectedWorktreeDetail: WorktreeDetail?` + async loader keyed
  to selection; cancel-on-reselect (mirror existing `loadTask`/`prFetchTask`
  pattern). Loads from the new detail service. Tested via mock.
- Create sheet: extend `addWorktree` to accept an explicit `folderName` and a
  `copyFiles` override (keep current random-name behavior as default). Tested.
- PR card review/checks read from the enriched `pullRequests[branch]`.

## 12. File plan

**New (Views/ — coverage-excluded):**
`Views/Theme/OMWTheme.swift`, `Views/Theme/GlassStyles.swift`;
`Views/MainWindow/MainWindowView.swift`, `GlassToolbar.swift`,
`RepositorySidebar.swift`, `WorktreeListColumn.swift`;
`Views/Detail/DetailPaneView.swift` (+ `DetailHero`, `DetailMetaGrid`,
`PRCardView`, `DiffStatBar`, `CopiedFilesChips`, `CommitListView`,
`DetailActionBar`); `Views/Components/{StatusDot,Badge,JobIndicator,GlassRoundButton,Toast,ContextMenuContent}.swift`;
`Views/Sheets/CreateWorktreeSheet.swift`, `Views/Settings/AppearanceSettingsView.swift`
(+ `AccentDotsPicker`/`AppearanceSegment` subviews). Restyle: `WorktreeRowView.swift`,
`ImportPRView.swift`, `SettingsView.swift` (add Appearance tab).

**New (tested):** `Models/{WorktreeDetail,Commit,DiffStat,AheadBehind}.swift`;
`Models/{AppearanceMode,AccentChoice}.swift`; `Services/WorktreeManager+Detail.swift`.

**Modified (tested):** `Models/PullRequestInfo.swift`,
`Services/PullRequestService.swift`, `ViewModels/WorktreeListViewModel.swift`
(+ maybe a `+Detail` extension), `OhMyWorktreeTests/MockPRGitExecutor.swift`.

**Modified (excluded):** `AppDelegate+Window.swift`, `ContentView.swift`,
`project.yml` (deployment target 26).

## 13. Coverage strategy

The 100% gate stays green by construction:
- All SwiftUI views live under `Views/**` → already excluded.
- New **models** (`WorktreeDetail`, `Commit`, `DiffStat`, `AheadBehind`,
  `AppearanceMode`, `AccentChoice`) are pure → 100% unit-tested (incl. name lookup,
  default fallback, and `nsAppearance`/RGB mappings).
- New **service** parsing (ahead/behind, diff, log) → 100% via `MockGitExecutor`
  (success, empty, no-upstream, binary, malformed lines).
- **PR** additions → 100% via `MockPRGitExecutor` (each review/check state).
- New **view-model** logic (search filter, detail load, create params) → tested;
  add to the temporary flaky-quarantine list only if a path proves nondeterministic
  on CI, with a reason (per `coverage-exclude.txt` convention).

## 14. Testing plan

- Models: encode/decode-free pure structs; equality + edge values.
- Detail service: golden git outputs → parsed structs; failure → nil/empty.
- PR service: golden `gh` JSON with each `statusCheckRollup`/`reviewDecision`.
- View-model: filter results; detail load populates/clears on selection change;
  create passes name/base/copy through.
- Gate: `swiftlint`, full `xcodebuild … test`, `scripts/coverage.sh` all green
  before every commit (per CLAUDE.md).

## 15. Phased rollout

0. **Target bump** — `project.yml` → macOS 26, `xcodegen generate`, build green.
1. **Tokens + components** — theme, glass styles, reusable bits.
2. **Window + toolbar + 3-column** — wired to existing data; detail uses
   placeholders for not-yet-computed figures.
3. **Detail backend** — models + service + tests; wire detail pane to real data.
4. **PR reviews/checks** — model/service/tests; PR card complete.
5. **Sheets + settings + chrome** — Create sheet; restyle Import/Settings; **add
   the Appearance tab** (Auto/Light/Dark + accent dots) with `AppearanceMode`/
   `AccentChoice` models, `@AppStorage` persistence, and live appearance/accent
   application; context menu; toast.
6. **Polish + gates** — pixel pass against dimensions, swiftlint, tests, coverage.

Each phase builds and keeps gates green; commits only when the user asks.

## 16. Risks & open items

- **Native glass on custom layouts:** `.glassEffect` is tuned for standard
  controls; the bespoke 52pt toolbar / pinned action bar may need a
  `GlassEffectContainer` + shape tuning to avoid seams. Validate visually early.
- **Traffic-light inset:** exact leading inset for the title under hidden-titlebar
  windows varies; measure against the running window.
- **`statusCheckRollup` shape** differs between checks and legacy statuses; the
  reducer must handle both (`conclusion` vs `state`).
- **Default-branch detection** for diff base can be wrong on repos without
  `origin/HEAD`; fallback chain `origin/HEAD → main → master → first commit`.
- **Create-sheet name semantics:** name = folder = branch (matches prototype's
  random-name generator); confirm this matches current `addWorktree` expectations.
