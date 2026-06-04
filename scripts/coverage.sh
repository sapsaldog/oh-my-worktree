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
