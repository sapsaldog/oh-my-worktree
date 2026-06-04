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


def self_test():
    _test_helpers()
    _test_report_and_eval()
    print("self-test: all assertions passed")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
