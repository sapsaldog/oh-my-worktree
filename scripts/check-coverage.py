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
import math
import os
import subprocess
import sys
from fnmatch import fnmatch

TARGET = "OhMyWorktree.app"
EXCLUDE_FILE = "coverage-exclude.txt"
DEBT_FILE = "coverage-debt.json"

# The app target has ~54 source files. If xccov reports far fewer (target
# renamed, schema drift, broken bundle), the gate must FAIL rather than pass
# having checked nothing.
MIN_APP_FILES = 40


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
                "percent": f["lineCoverage"] * 100.0,
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
    """Snapshot every sub-100%, non-excluded file, flooring its coverage to 1 decimal so a fresh --update always passes --check."""
    debt = {}
    for f in files:
        rp = f["relpath"]
        if is_excluded(rp, excludes):
            continue
        if f["executable"] - f["covered"] > 0:
            debt[rp] = math.floor(f["percent"] * 10) / 10
    return dict(sorted(debt.items()))


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
    try:
        report = run_xccov(xcresult)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as err:
        print(f"error: could not read coverage from {xcresult}: {err}",
              file=sys.stderr)
        return 2
    files = parse_report(report, TARGET, root)
    if len(files) < MIN_APP_FILES:
        print(f"error: only {len(files)} files found for target {TARGET!r} "
              f"(expected >= {MIN_APP_FILES}) — refusing to pass vacuously; "
              f"xccov schema drift or wrong target?", file=sys.stderr)
        return 2
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
    try:
        report = run_xccov(xcresult)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as err:
        print(f"error: could not read coverage from {xcresult}: {err}",
              file=sys.stderr)
        return 2
    files = parse_report(report, TARGET, root)
    if len(files) < MIN_APP_FILES:
        print(f"error: only {len(files)} files found for target {TARGET!r} "
              f"(expected >= {MIN_APP_FILES}) — refusing to overwrite "
              f"{DEBT_FILE}", file=sys.stderr)
        return 2
    debt = build_debt(files, excludes)
    with open(os.path.join(root, DEBT_FILE), "w") as fh:
        json.dump({"files": debt}, fh, indent=2)
        fh.write("\n")
    print(f"Wrote {DEBT_FILE}: {len(debt)} files in debt.")
    return 0


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

    fails = evaluate(files, excludes, {}, strict=False)
    assert len(fails) == 1 and "S.swift" in fails[0], fails

    fails = evaluate(files, excludes,
                     {"OhMyWorktree/Services/S.swift": 70.0}, strict=False)
    assert fails == [], fails

    regressed = [dict(f) for f in files]
    regressed[2]["covered"] = 6
    regressed[2]["percent"] = 60.0
    fails = evaluate(regressed, excludes,
                     {"OhMyWorktree/Services/S.swift": 70.0}, strict=False)
    assert len(fails) == 1 and "regressed" in fails[0], fails

    fails = evaluate(files, excludes, {}, strict=True)
    assert len(fails) == 1 and "strict" in fails[0], fails

    almost = [{"relpath": "OhMyWorktree/Models/A.swift", "executable": 10000,
               "covered": 9999, "percent": 99.99}]
    assert len(evaluate(almost, [], {}, strict=True)) == 1

    assert build_debt(files, excludes) == {
        "OhMyWorktree/Services/S.swift": 70.0}, build_debt(files, excludes)

    # build_debt must never set a floor ABOVE actual coverage, so a fresh
    # --update always produces floors that --check accepts. round() would
    # round 98.59% up to 98.6% and trip the gate; floor() must be used.
    jit = [{"relpath": "OhMyWorktree/Services/J.swift", "executable": 10000,
            "covered": 9859, "percent": 98.59}]
    jit_debt = build_debt(jit, [])
    assert jit_debt["OhMyWorktree/Services/J.swift"] <= 98.59 + 1e-9, jit_debt
    assert evaluate(jit, [], jit_debt, strict=False) == [], \
        "fresh debt floors must pass --check"


def self_test():
    _test_helpers()
    _test_report_and_eval()
    print("self-test: all assertions passed")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    for flag, handler in (("--update", cmd_update), ("--check", cmd_check)):
        if flag in argv:
            idx = argv.index(flag)
            if idx + 1 >= len(argv):
                print(f"error: {flag} requires an <xcresult> path",
                      file=sys.stderr)
                return 2
            return handler(argv[idx + 1])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
