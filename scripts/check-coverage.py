#!/usr/bin/env python3
"""Coverage gate for OhMyWorktree.

Parses `xcrun xccov view --report --json` output for the OhMyWorktree.app
target and enforces STRICT 100% line coverage on every non-excluded file:

  * non-excluded file at 100% (coveredLines == executableLines) -> pass
  * non-excluded file below 100%                                -> FAIL
  * excluded file (listed in coverage-exclude.txt)              -> skipped

There is no partial-credit / debt mechanism: a gated file is either 100% or it
must be added to coverage-exclude.txt (with a reason). The exclusion list is the
only knob, and shrinking it is the path to full coverage.

Usage:
  check-coverage.py --check <xcresult>    evaluate, exit 0 (pass) / 1 (fail)
  check-coverage.py --dump  <xcresult>    print per-file coverage (GATE|EXCL)
  check-coverage.py --self-test           run built-in unit tests (no Xcode)
"""
import json
import os
import subprocess
import sys
from fnmatch import fnmatch

TARGET = "OhMyWorktree.app"
EXCLUDE_FILE = "coverage-exclude.txt"
# The app target has ~54 source files. If xccov reports far fewer (target
# renamed, schema drift, broken bundle), fail rather than pass vacuously.
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


def evaluate(files, excludes):
    """Return failure strings; every non-excluded file must be 100%."""
    failures = []
    for f in files:
        rp = f["relpath"]
        if is_excluded(rp, excludes):
            continue
        if f["executable"] - f["covered"] > 0:
            failures.append(
                f"{rp}: {f['covered']}/{f['executable']} "
                f"({f['percent']:.1f}%) — must be 100%")
    return failures


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


def cmd_check(xcresult):
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
              f"(expected >= {MIN_APP_FILES}) — refusing to pass vacuously; "
              f"xccov schema drift or wrong target?", file=sys.stderr)
        return 2
    failures = evaluate(files, excludes)
    if failures:
        print(f"Coverage gate FAILED ({len(failures)} file(s) below 100%):")
        for line in failures:
            print("  " + line)
        return 1
    gated = sum(1 for f in files if not is_excluded(f["relpath"], excludes))
    print(f"Coverage gate passed (strict 100% on {gated} files).")
    return 0


def cmd_dump(xcresult):
    """Print per-file coverage (covered, executable, percent, GATE|EXCL)."""
    root = repo_root()
    excludes = parse_exclude(load_text(os.path.join(root, EXCLUDE_FILE)))
    files = parse_report(run_xccov(xcresult), TARGET, root)
    for f in sorted(files, key=lambda x: x["relpath"]):
        tag = "EXCL" if is_excluded(f["relpath"], excludes) else "GATE"
        print(f"{f['covered']}\t{f['executable']}\t{f['percent']:.1f}\t"
              f"{tag}\t{f['relpath']}")
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


def _test_evaluate():
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
    # excluded view skipped; 100% model passes; 70% service fails
    fails = evaluate(files, excludes)
    assert len(fails) == 1, fails
    assert "S.swift" in fails[0] and "must be 100%" in fails[0], fails

    # all non-excluded at 100% -> pass
    allcovered = [dict(f) for f in files]
    allcovered[2]["covered"] = 10
    assert evaluate(allcovered, excludes) == [], evaluate(allcovered, excludes)

    # integer 100% check: 9999/10000 (99.99%) still fails
    almost = [{"relpath": "OhMyWorktree/Models/A.swift", "executable": 10000,
               "covered": 9999, "percent": 99.99}]
    assert len(evaluate(almost, [])) == 1, "99.99% must fail strict 100%"

    # zero executable lines -> nothing to cover -> pass
    empty = [{"relpath": "OhMyWorktree/Models/E.swift", "executable": 0,
              "covered": 0, "percent": 100.0}]
    assert evaluate(empty, []) == [], "0 executable lines should pass"


def self_test():
    _test_helpers()
    _test_evaluate()
    print("self-test: all assertions passed")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    for flag, handler in (("--check", cmd_check), ("--dump", cmd_dump)):
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
