# Design: 100% Code Coverage Gate

**Date:** 2026-06-03
**Status:** Approved (design phase)
**Author:** brainstorming session

## Goal

Bring the OhMyWorktree app target to **100% line coverage** over an explicitly
documented set of files, and make CI **fail** when coverage regresses below the
required floor (ratcheting up to a hard 100% lock).

"100%" is defined as: **every non-excluded source file has
`coveredLines == executableLines`.** A small, explicitly listed set of files is
excluded as intentionally untested (UI bodies, app-lifecycle glue, and thin
system-call adapters). The exclusion list itself is the documentation of what we
choose not to test and why.

## Decisions (locked during brainstorming)

1. **Scope = whole app target + explicit exclusion list.** Measure the entire
   `OhMyWorktree.app` target; maintain an explicit exclusion list for genuinely
   untestable files. Enforce 100% on everything else.
2. **Tooling = custom script over `xccov` (zero new dependencies).** No Ruby
   (`xcov`/`slather`), no third-party services. Python 3 stdlib only.
3. **Borderline system services = maximal.** Refactor system-dependent services
   for dependency injection and test their logic; exclude only the irreducible
   system-call seam (isolated into a thin adapter file) plus Views/AppDelegate.
4. **Rollout = strict 100% immediately (no ratchet).** The gate requires every
   non-excluded file to be exactly 100% from the start — there is no debt/floor
   mechanism. A gated file is either 100% or it is on the exclusion list. CI is
   red until the gated files are brought to 100%; coverage work then drives it
   green file-by-file, and shrinking the exclusion list extends the gate.
   (Superseded the original "ratchet then lock" plan at the user's direction;
   `coverage-debt.json` was removed.)

## Background & constraints (evidence-based)

Measured on this machine (Xcode 15 toolchain, macOS 15), against a real
`-enableCodeCoverage YES` test run:

- ✅ `xcrun xccov view --report --json <xcresult>` reliably reports **per-file**
  coverage for **all app source files** under the `OhMyWorktree.app` target.
  Fields per file: `path` (absolute), `name`, `executableLines`,
  `coveredLines`, `lineCoverage`. The result bundle also contains a separate
  `OhMyWorktree.xctest` target (the test code's own coverage) which the gate
  **must ignore**.
- ❌ `xcrun llvm-cov export` does **not** work for app-source per-line data in
  this project's `TEST_HOST` / `BUNDLE_LOADER` configuration. The app's
  `__llvm_covmap` is not present in the app host binary, and the `.xctest`
  binary's coverage map contains only the **test** files (27 files, all under
  `OhMyWorktreeTests/`). Passing both binaries as objects does not change this.
- ❌ `xcrun xccov view --file <source> <xcresult>` fails with "unrecognized file
  format"; no `.xccovarchive` is produced under the derived data path.

**Consequence:** the gate is built on **file-level** xccov data. Per-line
"ignore" comment markers are **not** used (they cannot be reliably validated in
this setup). Instead, irreducible system-call seams are **isolated into small,
explicitly excluded adapter files**. This is simpler, is proven to work today,
and is better architecture (side effects isolated behind named seams).

## Coverage baseline (current)

App target overall: **58.63%** (4428 / 7552 executable lines).

| Category        | Coverage | Uncovered | Nature                                   |
|-----------------|---------:|----------:|------------------------------------------|
| Extensions      |   100.0% |         0 | Done                                     |
| Models          |    85.4% |        31 | Easily testable                          |
| ViewModels      |    75.1% |       231 | Mostly testable                          |
| Services        |    61.4% |       974 | Mixed: pure logic + system wrappers      |
| Views           |    49.5% |      1556 | SwiftUI bodies — exclude                  |
| AppDelegate/App |    58.2% |       332 | Menu-bar lifecycle — exclude              |

Largest uncovered files (informational; drives phase ordering):

- `ExternalToolLauncher.swift` — 41/467 (8.8%): per-tool `Process` command
  building; only the static `runCmuxOpenProtocol` is currently tested.
- `GitHeadMonitor.swift` — 6/117 (5.1%): `DispatchSource` file watcher.
- `WindowObserver.swift` — 4/102 (3.9%): AppKit `NSWindow` observation.
- `RepositoryStore.swift` — 176/251 (70.1%): actor-based JSON persistence.
- `WorktreeManager(+GitOps)`, `PullRequestService`, `BackgroundTaskQueue`,
  `NotificationManager`, `HotkeyManager`, `UpdaterManager`,
  `RandomNameGenerator`, `WorktreeFileCopier` — partial.

## Architecture

### Coverage run

```
xcodebuild test \
  -project OhMyWorktree.xcodeproj \
  -scheme OhMyWorktreeTests \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/CoverageResult.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

`-derivedDataPath` is fixed so artifact locations are deterministic in CI and
locally.

### Gate script — `scripts/check-coverage.py` (Python 3 stdlib only)

Inputs: the `.xcresult` path, `coverage-exclude.txt`, `coverage-debt.json`.

Algorithm:

1. Run `xcrun xccov view --report --json <xcresult>`; select the
   `OhMyWorktree.app` target only.
2. For each file, compute a **repo-relative path** by stripping the repo-root
   prefix from the absolute `path`. The repo root is resolved once via
   `git rev-parse --show-toplevel`.
3. Drop files matching any glob in `coverage-exclude.txt`.
4. For each remaining file, evaluate against the gate rule (below).
5. Print a per-file report of failures; exit non-zero if any file fails.

Gate rule per non-excluded file (`u = executableLines - coveredLines`):

- `u == 0` → **pass** (100%).
- `u > 0` → **fail** (write tests to reach 100%, or add the file to
  `coverage-exclude.txt` with a reason).

The 100% check is the **integer** comparison `coveredLines == executableLines`,
never a rounded percentage (avoids 99.96%-rounds-to-100% false passes). There is
no debt/floor mechanism: every non-excluded file must be 100%.

Modes:

- `--check` (used by CI): evaluate and exit 0/1.
- `--dump`: print per-file coverage (`covered  executable  percent  GATE|EXCL`)
  to inspect what is failing.
- `--self-test`: run built-in unit tests over synthetic coverage data
  (exclusion matching, per-file 100% pass/fail, integer-100% check, zero-line
  files). Runs in CI as a fast sanity check, independent of any Xcode build.

### Exclusion model (two files = the documentation)

**`coverage-exclude.txt`** — permanent, intentional exclusions. One glob per
line, `#` comments required to state the reason. Initial contents:

```
# SwiftUI view bodies — not unit-tested (excluded by design)
OhMyWorktree/Views/**

# Menu-bar / app lifecycle glue — requires a running NSApplication
OhMyWorktree/AppDelegate.swift
OhMyWorktree/AppDelegate+*.swift
OhMyWorktree/OhMyWorktreeApp.swift

# Thin system-call adapters (irreducible seams) — added as they are extracted
# e.g. OhMyWorktree/Services/<Name>+SystemSeam.swift
```

There is **no** `coverage-debt.json` / floor file. A non-excluded file is either
100% or it is listed in `coverage-exclude.txt` (with a reason). This is the only
knob; shrinking the exclusion list is the path to full coverage.

### Seam-isolation pattern (for the "maximal" refactors)

For each borderline service, separate **testable logic** from the **irreducible
system call**:

- Keep decision/command-building/parsing logic in the main file → must reach
  100%.
- Move the single side-effecting call (`process.run()`, `DispatchSource` setup,
  Carbon hotkey registration, Sparkle calls, `NSWorkspace`,
  `UNUserNotificationCenter`) behind a small injected protocol whose production
  implementation lives in a thin `*+SystemSeam.swift` (or similarly named) file
  on the exclusion list.

Example — `ExternalToolLauncher`: extract a `ProcessRunning` seam; unit-test
that `openInVSCode`/`openInITerm`/etc. build the correct executable + arguments
for each `OpenMode` by asserting on a recording fake runner. The real
`process.run()` lives in the excluded adapter.

### Nondeterministic coverage (flaky quarantine)

**Finding (Phase 0, evidence-based):** line coverage for files exercised through
async/concurrency/system paths is both **nondeterministic across runs** and
**non-portable between environments** (local vs CI on Xcode 16.4, headless).
Evidence:

- *Run-to-run (CI, 3 runs):* `BackgroundTaskQueue` 266–284/304; `Repository`
  7–10/10; `WorktreeListViewModel` 334–338/482; `GitCommandExecutor` 189–190/200.
- *Local vs CI:* `Worktree` 84% local but 51.5% CI; `ExternalToolLauncher`/
  `WorktreeListViewModel+ExternalTools` near-0% on CI (external tools absent).

Root cause: these tests exercise **concurrency races** (`withJobTimeout` timeout
paths, `rapidEnqueueAndCancelAll` cancellation) and **system/external paths**.
`await waitUntilIdle()` / `await confirmation` drain the queue but cannot pin
down *which internal lines* run — that depends on the scheduler and the host
environment. Deterministic, portable 100% on these files requires injecting
controllable clock/scheduler/process seams (P3-level work). A locally-stable
baseline (6 same-machine runs) was **not** enough — only CI runs revealed the
divergence. Lesson: characterize variance in CI's environment, not just locally.

A strict gate cannot sit on this: a floor set above what CI measures (or above a
future run) flakes CI red. **Decision: quarantine the affected files for Phase 0;
fix determinism/portability later.**

- Quarantined files go in `coverage-exclude.txt` under a clearly separated,
  TEMPORARY section. Two causes are documented: (a) varies run-to-run on CI,
  (b) stable but much lower on CI than locally. Phase-0 quarantine (11 files):
  `BackgroundTaskQueue`, `HotkeyManager`, `WorktreeManager`,
  `WorktreeManager+GitOps`, `OhMyWorktreeError`, `Repository`,
  `GitCommandExecutor`, `WorktreeListViewModel`, `Worktree`,
  `ExternalToolLauncher`, `WorktreeListViewModel+ExternalTools`.
- **Quarantine rule:** quarantine a file if its covered-line count varies across
  CI runs, OR if its CI coverage cannot yet be driven to a stable 100% (external
  tools absent, async timing, system event sources). These need
  clock/scheduler/process-seam refactoring before they can be gated at 100%.
- Resulting baseline: 21 gated files (8 already at 100%, 13 still below — the
  gate fails on those until tests bring them to 100%); 33 excluded (17 Views,
  5 AppDelegate/app, 11 quarantine).
- **Exit:** when a quarantined file's tests are made deterministic and portable
  (clock/scheduler/process injection) and it reaches 100%, remove it from the
  quarantine so the gate covers it. True "everything 100%" is reached when the
  quarantine holds only the structurally-untestable seams.

### CI integration — `.github/workflows/ci.yml`

Extend the existing `test` job (rename to "Build, Test & Coverage"):

1. `xccov self-test`: `python3 scripts/check-coverage.py --self-test`.
2. Build & test with coverage (command above).
3. Gate: `python3 scripts/check-coverage.py --check build/CoverageResult.xcresult`.

The `lint` job is unchanged. The gate step is what makes CI fail when coverage
is insufficient.

### Local ergonomics — `scripts/coverage.sh`

One command that mirrors CI: runs the coverage build + `--check`. Developers run
this before committing (alongside the existing SwiftLint + test requirement in
`CLAUDE.md`). Use `python3 scripts/check-coverage.py --dump <xcresult>` to see
each file's current coverage.

## Rollout phases

- **P0 — Gate infrastructure.** Add `check-coverage.py` (+ `--self-test`),
  `coverage.sh`, `coverage-exclude.txt` (Views + AppDelegate), and an initial
  `coverage-debt.json` snapshot of every currently-sub-100% non-excluded file.
  Wire CI. Result: CI enforces "no regression" immediately, still green.
- **P1 — Quick wins.** Models (`OhMyWorktreeError`, `Worktree`, `AppSettings`),
  pure Services (`RandomNameGenerator`, `WorktreeFileCopier`, remaining
  `GitCommandExecutor`). Tighten debt.
- **P2 — Git logic.** `WorktreeManager`, `WorktreeManager+GitOps`,
  `RepositoryStore`, `PullRequestService`, `BackgroundTaskQueue` via
  `MockGitExecutor`. Tighten debt.
- **P3 — Borderline service injection.** `ExternalToolLauncher`,
  `NotificationManager`, `GitHeadMonitor`, `WindowObserver`, `HotkeyManager`,
  `UpdaterManager`: extract seams, test the logic, exclude the adapters.
  Tighten debt.
- **P4 — ViewModels.** `WorktreeListViewModel`, `+ExternalTools`, `+QuickRemove`,
  `+ContextMenu`, `RepositoryListViewModel`, `HotkeyRecorderViewModel`,
  `ImportPRViewModel`. Tighten debt.
- **P5 — Lock.** Finalize `coverage-exclude.txt`, empty `coverage-debt.json`,
  confirm strict 100% passes locally and in CI.

Each phase keeps CI green and may land as its own PR.

## Testing & validation of the gate itself

- `check-coverage.py --self-test` covers: glob exclusion matching, repo-relative
  path derivation, per-file pass/fail, debt floor pass, debt floor regression
  fail, new-untested-file fail, strict-mode behaviour, integer 100% check
  (no float rounding pass).
- Methodology follows TDD (red → green) for both the script and the new Swift
  tests, per the repo's testing conventions.
- `swiftlint lint` and the full test suite must pass before each commit
  (existing `CLAUDE.md` rule).

## Deliverables

- `scripts/check-coverage.py`
- `scripts/coverage.sh`
- `coverage-exclude.txt`
- `coverage-debt.json`
- `.github/workflows/ci.yml` (modified)
- Source refactors: extracted system-seam adapter files + injected protocols
- New/expanded Swift Testing test files
- `CLAUDE.md` update (document the coverage gate + pre-commit step)

(`build/` is already in `.gitignore`, so coverage artifacts need no new ignore
entry.)

## Risks & mitigations

- **Stubborn unreachable lines** (e.g. `@unknown default`, `deinit`,
  `fatalError` guards) could block file-level 100%. Mitigation: make reachable
  via tests where reasonable; otherwise isolate into an excluded seam file. No
  per-line ignore mechanism exists, so each such line forces an explicit
  decision — which is the intent.
- **xccov output format drift across Xcode versions.** Mitigation: the script
  depends only on the documented `--report --json` shape (target → files →
  `{path, executableLines, coveredLines, lineCoverage}`), validated by
  `--self-test` against fixtures.
- **Effort.** ~900–1100 lines of behaviour to bring under test plus several
  refactors. Mitigation: phased rollout behind the ratchet; never blocks `main`.
- **Flaky/async services** (file watchers, queues) may be timing-sensitive under
  test. Mitigation: inject clocks/seams so tests are deterministic.

## Out of scope (YAGNI)

- Coverage of SwiftUI view bodies and `AppDelegate` lifecycle (excluded by
  design).
- Branch/region/MC-DC coverage — line coverage only.
- Third-party coverage services (Codecov/Coveralls) and HTML report hosting.
- Per-line ignore comment markers (unsupported in this test-host setup).
