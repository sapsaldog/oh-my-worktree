---
name: release
description: >
  Oh My Worktree release workflow with Sparkle auto-update and GitHub Releases.
  Use when the user says "release", "릴리스", "릴리즈", "배포", "새 버전",
  "bump version", "create release", "new version", or wants to publish a new
  version of Oh My Worktree to GitHub Releases with Sparkle appcast update.
---

# Oh My Worktree Release

## Prerequisites

- Sparkle EdDSA key in macOS Keychain (already configured)
- `xcodegen`, `gh` CLI installed
- Sparkle tools in DerivedData:

```bash
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*/sparkle/Sparkle/bin' -type d 2>/dev/null | head -1)"
```

## Workflow

Execute these steps in order. Ask the user for version number and release notes if not provided.

### 1. Bump Version

In `project.yml`, update:
- `CFBundleShortVersionString` — new version (e.g., "1.2.0")
- `CFBundleVersion` — increment build number by 1

Then run `xcodegen generate`.

### 2. Commit & Push Version Bump

```bash
git add project.yml OhMyWorktree/Info.plist
git commit -m "Bump version to {version}"
git push origin main
```

### 3. Archive, Extract & Re-sign .app

```bash
xcodebuild archive \
  -project OhMyWorktree.xcodeproj \
  -scheme OhMyWorktree \
  -archivePath build/OhMyWorktree.xcarchive

cp -R build/OhMyWorktree.xcarchive/Products/Applications/OhMyWorktree.app build/
```

**Re-sign the entire bundle** to ensure the app and embedded Sparkle.framework share the same ad-hoc signature. Without this, macOS rejects the app at launch due to Team ID mismatch between the main binary and the framework.

```bash
codesign --force --deep --sign - build/OhMyWorktree.app
```

Verify both have matching signatures:

```bash
codesign -dvv build/OhMyWorktree.app 2>&1 | grep -E "Signature|TeamIdentifier"
codesign -dvv build/OhMyWorktree.app/Contents/Frameworks/Sparkle.framework 2>&1 | grep -E "Signature|TeamIdentifier"
```

Both should show `Signature=adhoc` and `TeamIdentifier=not set`.

### 4. Create Zip

```bash
cd build && ditto -c -k --keepParent OhMyWorktree.app OhMyWorktree-{version}.zip && cd ..
```

Use `ditto`, not `zip` — preserves macOS metadata.

### 5. Verify Signature

```bash
$SPARKLE_BIN/sign_update build/OhMyWorktree-{version}.zip
```

Confirm `sparkle:edSignature=` appears. Verification only — `generate_appcast` signs automatically.

### 6. Generate appcast.xml

```bash
mkdir -p release
cp build/OhMyWorktree-{version}.zip release/
cp appcast.xml release/

$SPARKLE_BIN/generate_appcast \
  --download-url-prefix "https://github.com/sapsaldog/oh-my-worktree/releases/download/v{version}/" \
  release/

cp release/appcast.xml appcast.xml
```

### 7. Push appcast.xml (BEFORE GitHub Release)

```bash
git add appcast.xml
git commit -m "Update appcast for v{version}"
git push origin main
```

Order matters: appcast must be live before the download URL exists.

### 8. Create GitHub Release

```bash
gh release create v{version} \
  build/OhMyWorktree-{version}.zip \
  --title "v{version}" \
  --notes "{release_notes}"
```

### 9. Cleanup

```bash
rm -rf build/ release/
```

## Key Rules

- **Re-sign after archive** — `codesign --force --deep --sign -` on the .app bundle to unify Team IDs between main binary and Sparkle.framework
- **appcast.xml push BEFORE GitHub Release** — users fetch appcast from `raw.githubusercontent.com`
- **Version must be higher** than previous `CFBundleShortVersionString`
- **Backup EdDSA key** before switching machines: `$SPARKLE_BIN/generate_keys -x`

## Optional: Embedded Release Notes

Place HTML file alongside zip before step 6:

```bash
# release/OhMyWorktree-{version}.html
<h2>v{version}</h2>
<ul><li>Changes here</li></ul>
```
