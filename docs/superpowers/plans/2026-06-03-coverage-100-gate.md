# 100% Coverage Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a CI-enforced coverage gate that ratchets the OhMyWorktree app target toward 100% line coverage and fails the build on any regression.

**Architecture:** A dependency-free Python 3 script parses `xcrun xccov view --report --json` (file-level coverage for the `OhMyWorktree.app` target) and enforces a per-file policy against two checked-in files: `coverage-exclude.txt` (permanent intentional exclusions) and `coverage-debt.json` (transitional per-file floors that shrink to empty, at which point a strict 100% lock takes over). CI runs the script after the test build.

**Tech Stack:** Python 3 (stdlib only), `xcrun xccov`, `xcodebuild`, GitHub Actions, Swift Testing (for later phases).

**Scope of THIS plan:** Phase 0 — the gate infrastructure. It delivers a working, testable, no-regression gate at the current baseline (58.63%). Raising coverage to 100% happens in Phases 1–5 (see "Subsequent phases" at the end), each planned just-in-time because authoring real Swift tests requires reading each target file. This plan does **not** contain placeholder test code for those files.

> **Repo rules (must honor during execution):**
> - This repo's owner requires **explicit approval before any `git commit`**. Treat every "Commit" step as a checkpoint: stage the files, show `git status`, and ask before committing. Do not commit unattended.
> - `CLAUDE.md` requires `swiftlint lint` and the test suite to pass before committing **Swift** changes. Phase 0 touches no Swift, so for Phase 0 commits run the relevant gate (`--self-test` / `--check`) instead; Swift work in later phases must run SwiftLint + tests.
> - Source of truth for the design is `docs/superpowers/specs/2026-06-03-coverage-100-gate-design.md`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/check-coverage.py` | The gate. Pure helpers (path/glob/exclude parsing, report parsing, evaluation, debt building) + I/O orchestration (`--check`, `--update`, `--self-test`). |
| `scripts/coverage.sh` | Local one-command wrapper: coverage build + gate, mirrors CI. |
| `coverage-exclude.txt` | Permanent glob exclusions with reasons (Views, AppDelegate, future seam adapters). |
| `coverage-debt.json` | Transitional per-file floors for not-yet-100% non-excluded files. |
| `.github/workflows/ci.yml` | Modified: add self-test step + coverage gate step to the test job. |
| `CLAUDE.md` | Modified: document the gate and the pre-commit coverage step. |

The script is built in three tasks (helpers → evaluation → I/O) so each task ends with `--self-test` green. Then the data files, the CI wiring, the local wrapper, and the docs.

---

## Task 1: Gate script — pure helpers + self-test harness

**Files:**
- Create: `scripts/check-coverage.py`

- [ ] **Step 1: Write the script header, `main()` dispatch, and `_test_helpers()` self-test (helpers not yet defined)**

Create `scripts/check-coverage.py` with exactly this content:

```python
#!/usr/bin/env python3
"""Coverage gate for OhMyWorktree.

Parses `xcrun xccov view --report --json` output for the OhMyWorktree.app
target and enforces a per-file coverage policy:

  * non-excluded file at 100% (coveredLines == executableLines) -> pass
  * non-excluded file below 100% but listed in coverage-debt.json with a floor
    it still meets -> pass (no regression)
  * non-excluded file below 100% and not in the debt list -> fail
  * strict mode (empty debt list): any non-excluded file below 100% -> fail

Usage:
  check-coverage.py --check <xcresult>     evaluate, exit 0/1
  check-coverage.py --update <xcresult>    rewrite coverage-debt.json from run
  check-coverage.py --self-test            run built-in unit tests (no Xcode)
"""
import json
import os
import subprocess
import sys
from fnmatch import fnmatch

TARGET = "OhMyWorktree.app"
EXCLUDE_FILE = "coverage-exclude.txt"
DEBT_FILE = "coverage-debt.json"


def repo_relative(path, root):
    root = root.rstrip("/") + "/"
    return path[len(root):] if path.startswith(root) else path


def match_glob(relpath, pattern):
    if pattern.endswith("/**"):
        prefix = pattern[:-3]
        return relpath == prefix or relpath.startswith(prefix + "/")
    return fnmatch(relpath, pattern)


def is_excluded(relpath, patterns):
    return any(match_glob(relpath, p) for p in patterns)


def parse_exclude(text):
    patterns = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        patterns.append(line)
    return patterns


def _test_helpers():
    assert repo_relative("/a/b/c/x.swift", "/a/b/c") == "x.swift"
    assert repo_relative("/a/b/c/d/x.swift", "/a/b/c/") == "d/x.swift"
    assert repo_relative("/other/x.swift", "/a/b/c") == "/other/x.swift"
    assert match_glob("OhMyWorktree/Views/X.swift", "OhMyWorktree/Views/**")
    assert match_glob("OhMyWorktree/Views/Sub/Y.swift", "OhMyWorktree/Views/**")
    assert not match_glob("OhMyWorktree/ViewsX/Y.swift", "OhMyWorktree/Views/**")
    assert match_glob("OhMyWorktree/AppDelegate+Menu.swift",
                      "OhMyWorktree/AppDelegate+*.swift")
    assert not match_glob("OhMyWorktree/AppDelegate.swift",
                          "OhMyWorktree/AppDelegate+*.swift")
    assert is_excluded("OhMyWorktree/Views/X.swift", ["OhMyWorktree/Views/**"])
    assert not is_excluded("OhMyWorktree/Models/M.swift",
                           ["OhMyWorktree/Views/**"])
    assert parse_exclude("# c\n\nA/**\n B.swift \n") == ["A/**", "B.swift"]


def self_test():
    _test_helpers()
    print("self-test: all assertions passed")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 2: Run the self-test to verify it passes**

Run: `python3 scripts/check-coverage.py --self-test`
Expected: `self-test: all assertions passed` and exit code 0.

(Helpers and their assertions were written together; this task's "red" is any
assertion failure or `NameError`. If it prints the passing line, the helpers are
correct.)

- [ ] **Step 3: Verify the no-arg path prints usage**

Run: `python3 scripts/check-coverage.py; echo "exit=$?"`
Expected: prints the module docstring and `exit=2`.

- [ ] **Step 4: Commit (checkpoint — ask before committing)**

```bash
git add scripts/check-coverage.py
git status
git commit -m "feat(coverage): add coverage-gate helpers with self-test"
```

---

## Task 2: Gate script — report parsing, evaluation, debt building

**Files:**
- Modify: `scripts/check-coverage.py`

- [ ] **Step 1: Add `parse_report`, `evaluate`, `build_debt` functions**

Insert these three functions immediately **after** `parse_exclude` (before
`_test_helpers`):

```python
def parse_report(report, target_name, root):
    """Return [{relpath, executable, covered, percent}] for one target."""
    files = []
    for target in report.get("targets", []):
        if target.get("name") != target_name:
            continue
        for f in target.get("files", []):
            files.append({
                "relpath": repo_relative(f["path"], root),
                "executable": f["executableLines"],
                "covered": f["coveredLines"],
                "percent": f.get("lineCoverage", 0.0) * 100.0,
            })
    return files


def evaluate(files, excludes, debt, strict):
    """Return a list of human-readable failure strings ([] means pass)."""
    failures = []
    for f in files:
        rp = f["relpath"]
        if is_excluded(rp, excludes):
            continue
        uncovered = f["executable"] - f["covered"]
        if uncovered == 0:
            continue
        if strict:
            failures.append(
                f"{rp}: {f['covered']}/{f['executable']} "
                f"({f['percent']:.1f}%) — must be 100% (strict lock)")
            continue
        if rp in debt:
            floor = debt[rp]
            if f["percent"] + 1e-9 < floor:
                failures.append(
                    f"{rp}: regressed to {f['percent']:.1f}% "
                    f"(floor {floor:.1f}%)")
            continue
        failures.append(
            f"{rp}: {f['covered']}/{f['executable']} "
            f"({f['percent']:.1f}%) — untested file not in debt list")
    return failures


def build_debt(files, excludes):
    """Snapshot every sub-100%, non-excluded file as {relpath: percent}."""
    debt = {}
    for f in files:
        rp = f["relpath"]
        if is_excluded(rp, excludes):
            continue
        if f["executable"] - f["covered"] > 0:
            debt[rp] = round(f["percent"], 1)
    return dict(sorted(debt.items()))
```

- [ ] **Step 2: Add `_test_report_and_eval()` and call it from `self_test`**

Add this function immediately **after** `_test_helpers`:

```python
def _test_report_and_eval():
    root = "/repo"
    report = {"targets": [
        {"name": "OhMyWorktree.xctest", "files": [
            {"path": "/repo/OhMyWorktreeTests/T.swift",
             "executableLines": 4, "coveredLines": 1, "lineCoverage": 0.25}]},
        {"name": "OhMyWorktree.app", "files": [
            {"path": "/repo/OhMyWorktree/Views/V.swift",
             "executableLines": 10, "coveredLines": 0, "lineCoverage": 0.0},
            {"path": "/repo/OhMyWorktree/Models/M.swift",
             "executableLines": 10, "coveredLines": 10, "lineCoverage": 1.0},
            {"path": "/repo/OhMyWorktree/Services/S.swift",
             "executableLines": 10, "coveredLines": 7, "lineCoverage": 0.7}]},
    ]}
    files = parse_report(report, "OhMyWorktree.app", root)
    assert [f["relpath"] for f in files] == [
        "OhMyWorktree/Views/V.swift",
        "OhMyWorktree/Models/M.swift",
        "OhMyWorktree/Services/S.swift",
    ], files  # test target excluded, app target only

    excludes = ["OhMyWorktree/Views/**"]

    # excluded view skipped; 100% model passes; service not in debt -> fail
    fails = evaluate(files, excludes, {}, strict=False)
    assert len(fails) == 1 and "S.swift" in fails[0], fails

    # service in debt at its floor -> pass
    fails = evaluate(files, excludes,
                     {"OhMyWorktree/Services/S.swift": 70.0}, strict=False)
    assert fails == [], fails

    # service regressed below floor -> fail
    regressed = [dict(f) for f in files]
    regressed[2]["covered"] = 6
    regressed[2]["percent"] = 60.0
    fails = evaluate(regressed, excludes,
                     {"OhMyWorktree/Services/S.swift": 70.0}, strict=False)
    assert len(fails) == 1 and "regressed" in fails[0], fails

    # strict mode: any sub-100 non-excluded file fails
    fails = evaluate(files, excludes, {}, strict=True)
    assert len(fails) == 1 and "strict" in fails[0], fails

    # integer 100% check: 9999/10000 (99.99%) still fails in strict mode
    almost = [{"relpath": "OhMyWorktree/Models/A.swift", "executable": 10000,
               "covered": 9999, "percent": 99.99}]
    assert len(evaluate(almost, [], {}, strict=True)) == 1

    # build_debt captures only sub-100 non-excluded files
    assert build_debt(files, excludes) == {
        "OhMyWorktree/Services/S.swift": 70.0}, build_debt(files, excludes)
```

Then change `self_test` to call it:

```python
def self_test():
    _test_helpers()
    _test_report_and_eval()
    print("self-test: all assertions passed")
    return 0
```

- [ ] **Step 3: Run the self-test to verify it passes**

Run: `python3 scripts/check-coverage.py --self-test`
Expected: `self-test: all assertions passed`, exit 0.

- [ ] **Step 4: Commit (checkpoint — ask before committing)**

```bash
git add scripts/check-coverage.py
git commit -m "feat(coverage): add report parsing, evaluation, debt building"
```

---

## Task 3: Gate script — I/O orchestration (`--check` / `--update`)

**Files:**
- Modify: `scripts/check-coverage.py`

- [ ] **Step 1: Add I/O + orchestration functions**

Insert these functions immediately **after** `build_debt` (before
`_test_helpers`):

```python
def repo_root():
    return subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True).strip()


def run_xccov(xcresult):
    out = subprocess.check_output(
        ["xcrun", "xccov", "view", "--report", "--json", xcresult], text=True)
    return json.loads(out)


def load_text(path):
    try:
        with open(path) as fh:
            return fh.read()
    except FileNotFoundError:
        return ""


def load_debt(path):
    try:
        with open(path) as fh:
            return json.load(fh).get("files", {})
    except FileNotFoundError:
        return {}


def cmd_check(xcresult):
    root = repo_root()
    excludes = parse_exclude(load_text(os.path.join(root, EXCLUDE_FILE)))
    debt = load_debt(os.path.join(root, DEBT_FILE))
    files = parse_report(run_xccov(xcresult), TARGET, root)
    strict = len(debt) == 0
    failures = evaluate(files, excludes, debt, strict)
    if failures:
        print("Coverage gate FAILED:")
        for line in failures:
            print("  " + line)
        return 1
    mode = "strict 100% lock" if strict else f"ratchet, {len(debt)} in debt"
    print(f"Coverage gate passed ({mode}).")
    return 0


def cmd_update(xcresult):
    root = repo_root()
    excludes = parse_exclude(load_text(os.path.join(root, EXCLUDE_FILE)))
    files = parse_report(run_xccov(xcresult), TARGET, root)
    debt = build_debt(files, excludes)
    with open(os.path.join(root, DEBT_FILE), "w") as fh:
        json.dump({"files": debt}, fh, indent=2)
        fh.write("\n")
    print(f"Wrote {DEBT_FILE}: {len(debt)} files in debt.")
    return 0
```

- [ ] **Step 2: Replace `main()` to dispatch `--check` and `--update`**

Replace the existing `main` function with:

```python
def main(argv):
    if "--self-test" in argv:
        return self_test()
    if "--update" in argv:
        return cmd_update(argv[argv.index("--update") + 1])
    if "--check" in argv:
        return cmd_check(argv[argv.index("--check") + 1])
    print(__doc__)
    return 2
```

- [ ] **Step 3: Verify self-test still passes (no Xcode needed)**

Run: `python3 scripts/check-coverage.py --self-test`
Expected: `self-test: all assertions passed`, exit 0.

- [ ] **Step 4: Commit (checkpoint — ask before committing)**

```bash
git add scripts/check-coverage.py
git commit -m "feat(coverage): add xccov I/O and --check/--update commands"
```

---

## Task 4: Initial exclusion list

**Files:**
- Create: `coverage-exclude.txt`

- [ ] **Step 1: Create `coverage-exclude.txt`**

Create `coverage-exclude.txt` (repo root) with exactly:

```
# Coverage exclusions — files intentionally NOT unit-tested.
# One glob per line, relative to repo root. `dir/**` excludes a whole subtree.
# Every entry must state a reason. See
# docs/superpowers/specs/2026-06-03-coverage-100-gate-design.md.

# SwiftUI view bodies — not unit-tested (excluded by design).
OhMyWorktree/Views/**

# Menu-bar / app lifecycle glue — requires a running NSApplication.
OhMyWorktree/AppDelegate.swift
OhMyWorktree/AppDelegate+*.swift
OhMyWorktree/OhMyWorktreeApp.swift

# Thin system-call adapters (irreducible seams) are appended here as they are
# extracted in later phases, e.g.:
# OhMyWorktree/Services/<Name>+SystemSeam.swift
```

- [ ] **Step 2: Verify the globs match the intended files and nothing else**

Run:
```bash
python3 - <<'PY'
import subprocess, sys
sys.path.insert(0, "scripts")
import importlib.util
spec = importlib.util.spec_from_file_location("cc", "scripts/check-coverage.py")
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
pats = cc.parse_exclude(open("coverage-exclude.txt").read())
root = subprocess.check_output(["git","rev-parse","--show-toplevel"],text=True).strip()
import glob, os
swift = [os.path.relpath(p, root) for p in glob.glob("OhMyWorktree/**/*.swift", recursive=True)]
excluded = sorted(f for f in swift if cc.is_excluded(f, pats))
for f in excluded: print("EXCLUDED:", f)
print("total excluded:", len(excluded))
PY
```
Expected: every file under `OhMyWorktree/Views/`, the four `AppDelegate*`/app
files, and nothing under `Models/`, `Services/`, `ViewModels/`, or
`Extensions/`.

- [ ] **Step 3: Commit (checkpoint — ask before committing)**

```bash
git add coverage-exclude.txt
git commit -m "feat(coverage): add initial exclusion list (Views, AppDelegate)"
```

---

## Task 5: Snapshot the initial debt list and verify the gate passes

**Files:**
- Create: `coverage-debt.json` (generated)

- [ ] **Step 1: Run a coverage build**

Run:
```bash
mkdir -p build && rm -rf build/CoverageResult.xcresult build/DerivedData
xcodebuild test \
  -project OhMyWorktree.xcodeproj \
  -scheme OhMyWorktreeTests \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/CoverageResult.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Generate the debt snapshot**

Run: `python3 scripts/check-coverage.py --update build/CoverageResult.xcresult`
Expected: `Wrote coverage-debt.json: N files in debt.` (N ≈ 25–30). Inspect the
file: it should list `Models/`, `ViewModels/`, and `Services/` files that are
currently below 100%, each with its current percentage; it must **not** contain
any `Views/` or `AppDelegate*` entries.

- [ ] **Step 3: Verify `--check` passes at the snapshot (no regression)**

Run: `python3 scripts/check-coverage.py --check build/CoverageResult.xcresult; echo "exit=$?"`
Expected: `Coverage gate passed (ratchet, N in debt).` and `exit=0`.

- [ ] **Step 4: Verify the gate FAILS when a floor is artificially raised**

Run:
```bash
python3 - <<'PY'
import json
d = json.load(open("coverage-debt.json"))
k = next(iter(d["files"]))
d["files"][k] = 100.0          # demand 100% from a file that isn't
json.dump(d, open("/tmp/debt-bad.json","w"))
print("tightened", k, "-> 100.0")
PY
cp coverage-debt.json /tmp/debt-good.json
cp /tmp/debt-bad.json coverage-debt.json
python3 scripts/check-coverage.py --check build/CoverageResult.xcresult; echo "exit=$?"
cp /tmp/debt-good.json coverage-debt.json   # restore
```
Expected: the run prints `Coverage gate FAILED:` with a `regressed` line and
`exit=1`; after restore the file is back to the good snapshot.

- [ ] **Step 5: Commit (checkpoint — ask before committing)**

```bash
git add coverage-debt.json
git commit -m "feat(coverage): snapshot initial coverage debt baseline"
```

---

## Task 6: Local wrapper script

**Files:**
- Create: `scripts/coverage.sh`

- [ ] **Step 1: Create `scripts/coverage.sh`**

Create `scripts/coverage.sh` with exactly:

```bash
#!/usr/bin/env bash
# Local coverage gate — mirrors CI. Usage:
#   scripts/coverage.sh            build + test + gate check
#   scripts/coverage.sh --update   build + test + rewrite coverage-debt.json
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
RESULT="build/CoverageResult.xcresult"
mkdir -p build
rm -rf "$RESULT" build/DerivedData
xcodebuild test \
  -project OhMyWorktree.xcodeproj \
  -scheme OhMyWorktreeTests \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "$RESULT" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
if [ "${1:-}" = "--update" ]; then
  python3 scripts/check-coverage.py --update "$RESULT"
else
  python3 scripts/check-coverage.py --check "$RESULT"
fi
```

- [ ] **Step 2: Make it executable and run it**

Run:
```bash
chmod +x scripts/coverage.sh
scripts/coverage.sh; echo "exit=$?"
```
Expected: test build succeeds, then `Coverage gate passed (ratchet, N in debt).`
and `exit=0`.

- [ ] **Step 3: Commit (checkpoint — ask before committing)**

```bash
git add scripts/coverage.sh
git commit -m "feat(coverage): add local coverage.sh wrapper"
```

---

## Task 7: Wire the gate into CI

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Replace the `test` job with the coverage-enabled version**

In `.github/workflows/ci.yml`, replace the entire `test:` job (currently
"Build & Test") with:

```yaml
  test:
    name: Build, Test & Coverage
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Coverage gate self-test
        run: python3 scripts/check-coverage.py --self-test

      - name: Build & Test (with coverage)
        run: |
          xcodebuild test \
            -project OhMyWorktree.xcodeproj \
            -scheme OhMyWorktreeTests \
            -destination 'platform=macOS' \
            -enableCodeCoverage YES \
            -derivedDataPath build/DerivedData \
            -resultBundlePath build/CoverageResult.xcresult \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY=""

      - name: Coverage gate
        run: python3 scripts/check-coverage.py --check build/CoverageResult.xcresult
```

Leave the `lint` job unchanged.

- [ ] **Step 2: Validate the workflow YAML parses**

Run:
```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('yaml ok')" 2>/dev/null \
  || python3 -c "import json; print('yaml module absent — skip (CI will parse)')"
```
Expected: `yaml ok` (or the skip notice if PyYAML isn't installed locally).

- [ ] **Step 3: Dry-run the CI command sequence locally**

Run:
```bash
python3 scripts/check-coverage.py --self-test \
  && scripts/coverage.sh \
  && echo "CI sequence OK"
```
Expected: ends with `CI sequence OK`.

- [ ] **Step 4: Commit (checkpoint — ask before committing)**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: enforce coverage gate in the test job"
```

---

## Task 8: Document the gate

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add a "Coverage" subsection under "Git Workflow" in `CLAUDE.md`**

In `CLAUDE.md`, immediately after the existing bullet that begins
"**Before every git commit**, you MUST run `swiftlint lint` and ...", add:

```markdown

### Code Coverage

- The `OhMyWorktree.app` target is gated at **100% line coverage** over all
  non-excluded files. CI fails when a non-excluded file drops below its floor.
- Run the gate locally before pushing: `scripts/coverage.sh`
- Exclusions live in `coverage-exclude.txt` (globs + reasons). The transitional
  per-file floors live in `coverage-debt.json`; when it is empty, a strict 100%
  lock is in force.
- After adding tests that raise coverage, update floors with
  `scripts/coverage.sh --update` and commit the new `coverage-debt.json`.
- Design + rollout: `docs/superpowers/specs/2026-06-03-coverage-100-gate-design.md`.
```

- [ ] **Step 2: Verify the section renders and links resolve**

Run:
```bash
grep -n "Code Coverage" CLAUDE.md
test -f docs/superpowers/specs/2026-06-03-coverage-100-gate-design.md && echo "spec link ok"
```
Expected: the heading line is found and `spec link ok` prints.

- [ ] **Step 3: Commit (checkpoint — ask before committing)**

```bash
git add CLAUDE.md
git commit -m "docs: document the coverage gate in CLAUDE.md"
```

---

## Phase 0 done — Definition of Done

- `python3 scripts/check-coverage.py --self-test` passes.
- `scripts/coverage.sh` builds, tests, and prints `Coverage gate passed`.
- CI has a self-test step + a coverage gate step that would fail on regression.
- `coverage-exclude.txt` and `coverage-debt.json` are committed; the gate is
  green at the current baseline and red on any per-file regression.

At this point the **CI-enforced gate (the user's second requirement) is live**.
Coverage is held at today's level and can only ratchet up.

---

## Subsequent phases (1–5): raising coverage to 100%

These are **not** pre-written here because each requires reading the specific
source file to author real Swift Testing tests (the no-placeholder rule). Plan
and execute them one at a time using the per-file recipe below. Phase ordering
and targets come from the spec.

**Per-file recipe (repeat until `coverage-debt.json` is empty):**

1. Pick the next file from `coverage-debt.json` (follow spec phase order:
   P1 Models + pure Services → P2 Git logic → P3 borderline service injection →
   P4 ViewModels).
2. Read the file and its existing test (if any). Identify uncovered behavior
   (open the `.xcresult` in Xcode's coverage report, or reason from the source).
3. For **borderline system services** (P3): extract the irreducible system call
   into a thin `<Name>+SystemSeam.swift` behind an injected protocol; add that
   adapter path to `coverage-exclude.txt` with a reason; keep all logic in the
   testable file.
4. Write Swift Testing tests (TDD: red → green) until the file reaches 100%.
   Run `swiftlint lint` and the test suite (per `CLAUDE.md`).
5. `scripts/coverage.sh --update` to lower/remove the file's debt floor; review
   the `coverage-debt.json` diff.
6. Commit (checkpoint — ask first): tests + any seam refactor + updated debt.

**P5 — Lock:** when `coverage-debt.json` is `{"files": {}}`, the gate is already
in strict mode (`cmd_check` sets `strict = len(debt) == 0`). Run
`scripts/coverage.sh` to confirm `Coverage gate passed (strict 100% lock).`,
then commit the empty debt file. No code change is needed to "flip" the lock.

Each subsequent file is its own small plan via subagent-driven-development:
read → write tests → update debt → checkpoint.
```