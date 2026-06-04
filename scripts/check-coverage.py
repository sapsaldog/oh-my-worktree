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
