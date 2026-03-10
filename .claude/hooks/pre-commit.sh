#!/bin/bash
# Claude Code PreToolUse hook: runs SwiftLint + tests before git commit

input=$(cat)

# Only intercept git commit commands
if ! echo "$input" | python3 -c "
import sys, json
d = json.load(sys.stdin)
exit(0 if 'git commit' in d.get('command', '') else 1)
" 2>/dev/null; then
  exit 0
fi

echo "Pre-commit: Running SwiftLint..."
if ! swiftlint lint; then
  echo "❌ SwiftLint failed. Commit blocked."
  exit 2
fi
echo "✅ SwiftLint passed"

echo "Pre-commit: Running tests..."
if ! xcodebuild \
  -project OhMyWorktree.xcodeproj \
  -scheme OhMyWorktreeTests \
  -destination 'platform=macOS' \
  test; then
  echo "❌ Tests failed. Commit blocked."
  exit 2
fi
echo "✅ Tests passed"
