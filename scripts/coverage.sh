#!/usr/bin/env bash
# Local coverage gate — mirrors CI. Builds, tests, and enforces STRICT 100%
# line coverage on every non-excluded file (see coverage-exclude.txt).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# The Xcode project is gitignored and generated from project.yml.
xcodegen generate
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
python3 scripts/check-coverage.py --check "$RESULT"
