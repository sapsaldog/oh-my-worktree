# Copied-file Diff-Tool Hand-off Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the in-app inline diff for `.worktreeinclude` copied files with a hand-off that opens each file's `main`↔`worktree` pair in a user-chosen external diff tool, selected from a picker shown in the detail section, the browser, and Settings.

**Architecture:** A pure, table-driven `DiffTool` catalog (100%-covered) holds the five tools and assembles launch arguments. An impure, coverage-excluded `DiffToolLauncher` detects installed tools and runs the process. The selected tool persists via `@AppStorage("diffToolID")`; a reusable `DiffToolMenu` SwiftUI view renders it in three places. The in-app `UnifiedDiffView` and the apply-to-main / copy-to-worktree actions are removed.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing, XcodeGen, `Process`/`FileManager`, SwiftLint.

**Spec:** `docs/superpowers/specs/2026-06-18-copied-file-diff-tool-handoff-design.md`

---

## Project conventions (read before starting)

- **Regenerate the Xcode project after adding/removing files:** `xcodegen generate` (sources are
  directory-globbed, so new files under `OhMyWorktree/` and `OhMyWorktreeTests/` are auto-included).
- **Build:** `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
- **Test:** `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`
- **Lint:** `swiftlint lint`
- **Coverage gate (strict 100% on non-excluded files):** `scripts/coverage.sh`
- **Commits:** This user forbids automatic commits. Treat every "Commit" step below as **optional —
  perform it only if the user explicitly asks**. Per `CLAUDE.md`, before any commit you MUST run
  `swiftlint lint` and the test scheme. The task boundary that matters is the **verification**
  (build + lint + tests), not the commit.
- **Coverage seams:** `Views/**`, `ExternalToolLauncher.swift`, `WorktreeListViewModel*.swift` are
  already in `coverage-exclude.txt`. The only NEW file that must reach 100% is the pure
  `DiffTool.swift`; `DiffToolLauncher.swift` gets added to the exclude list.

---

## File structure

**Create:**
- `OhMyWorktree/Models/DiffTool.swift` — pure catalog + arg/filter logic (100% covered).
- `OhMyWorktreeTests/DiffToolTests.swift` — unit tests for the catalog.
- `OhMyWorktree/Services/DiffToolLauncher.swift` — detection + `Process` launch (coverage-excluded).
- `OhMyWorktree/Views/Detail/DiffToolMenu.swift` — reusable picker view.

**Modify:**
- `OhMyWorktree/ViewModels/WorktreeListViewModel.swift` — inject launcher, drop `pendingApply`.
- `OhMyWorktree/ViewModels/WorktreeListViewModel+ExternalTools.swift` — `availableDiffTools`, `openInDiffTool`.
- `OhMyWorktree/ViewModels/WorktreeListViewModel+CopiedFiles.swift` — drop apply/openCopiedDiff, slim state.
- `OhMyWorktree/Views/Detail/CopiedFilesSection.swift` — menu in header, chip → hand-off.
- `OhMyWorktree/Views/Detail/CopiedFilesBrowser.swift` — drop diff drill-in/apply, menu in header, rows → hand-off.
- `OhMyWorktree/Views/Detail/CopiedFileRow.swift` — external-link affordance.
- `OhMyWorktree/Views/Detail/DetailPaneView.swift` — pass tools + callback.
- `OhMyWorktree/Views/Detail/CopiedFilesPresentation.swift` — drop apply confirm alert.
- `OhMyWorktree/Views/ContentView.swift` — wire hand-off, drop apply wiring.
- `OhMyWorktree/Views/GeneralSettingsView.swift` — "Diff tool" row.
- `OhMyWorktree/Services/CopiedFileDiffer.swift` — remove `applyToMain`/`applyToWorktree`.
- `OhMyWorktreeTests/CopiedFileDifferTests.swift` — remove apply tests.
- `coverage-exclude.txt` — add `DiffToolLauncher.swift`.

**Delete:**
- `OhMyWorktree/Views/Detail/UnifiedDiffView.swift`.

---

## Task 1: `DiffTool` pure catalog (TDD, must hit 100%)

**Files:**
- Create: `OhMyWorktree/Models/DiffTool.swift`
- Test: `OhMyWorktreeTests/DiffToolTests.swift`

- [ ] **Step 1: Write the failing test**

Create `OhMyWorktreeTests/DiffToolTests.swift`:

```swift
import Testing

@testable import OhMyWorktree

@Suite
struct DiffToolTests {

    @Test func catalogHasTheFiveDesignTools() {
        #expect(DiffTool.all.map(\.id) == ["araxis", "kaleidoscope", "bcompare", "vscode", "filemerge"])
        #expect(DiffTool.all.map(\.name) == [
            "Araxis Merge", "Kaleidoscope", "Beyond Compare", "VS Code", "FileMerge",
        ])
    }

    @Test func findReturnsToolByIDOrNil() {
        #expect(DiffTool.find(id: "vscode")?.name == "VS Code")
        #expect(DiffTool.find(id: "nope") == nil)
    }

    @Test func vscodeArgsIncludeDiffFlagOthersDoNot() {
        let vscode = DiffTool.find(id: "vscode")!
        #expect(vscode.launchArguments(mainPath: "/m", worktreePath: "/w") == ["--diff", "/m", "/w"])
        let araxis = DiffTool.find(id: "araxis")!
        #expect(araxis.launchArguments(mainPath: "/m", worktreePath: "/w") == ["/m", "/w"])
    }

    @Test func everyToolHasAtLeastOneCommandCandidate() {
        for tool in DiffTool.all {
            #expect(!tool.commandCandidates.isEmpty)
            #expect(!tool.sfSymbol.isEmpty)
        }
    }

    @Test func araxisPrefersBundledCompareOverPathToAvoidImageMagickClash() {
        // ImageMagick also ships a `compare`; the in-bundle path must come first.
        #expect(DiffTool.find(id: "araxis")!.commandCandidates.first
            == "/Applications/Araxis Merge.app/Contents/Utilities/compare")
    }

    @Test func installedFiltersByProbe() {
        let installed = DiffTool.installed { $0.id == "vscode" || $0.id == "filemerge" }
        #expect(installed.map(\.id) == ["vscode", "filemerge"])
    }

    @Test func effectiveUsesStoredWhenInstalled() {
        let installed = DiffTool.all
        #expect(DiffTool.effective(storedID: "bcompare", installed: installed)?.id == "bcompare")
    }

    @Test func effectiveFallsBackToFirstInstalledWhenStoredMissingOrNil() {
        let installed = [DiffTool.find(id: "vscode")!, DiffTool.find(id: "filemerge")!]
        #expect(DiffTool.effective(storedID: "araxis", installed: installed)?.id == "vscode")
        #expect(DiffTool.effective(storedID: nil, installed: installed)?.id == "vscode")
    }

    @Test func effectiveIsNilWhenNothingInstalled() {
        #expect(DiffTool.effective(storedID: "vscode", installed: []) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodegen generate && xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`
Expected: FAIL — build error, `DiffTool` is undefined.

- [ ] **Step 3: Write the implementation**

Create `OhMyWorktree/Models/DiffTool.swift`:

```swift
import Foundation

/// A pure, table-driven catalog of external diff/merge tools the app can hand a
/// copied file off to. Holds display metadata, the CLI invocation, and the
/// candidate command paths used for detection. All logic here is side-effect free
/// so it is fully unit-tested; the actual detection + `Process` launch live in the
/// coverage-excluded `DiffToolLauncher`.
struct DiffTool: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// SF Symbol used in the picker.
    let sfSymbol: String
    /// Flags inserted before the two file paths (e.g. VS Code's `--diff`).
    let extraArguments: [String]
    /// Absolute command paths tried in order; the first that exists wins.
    let commandCandidates: [String]

    /// Full argument vector for diffing `mainPath` (left) against `worktreePath` (right).
    func launchArguments(mainPath: String, worktreePath: String) -> [String] {
        extraArguments + [mainPath, worktreePath]
    }

    /// The five tools from the design, in display order.
    static let all: [DiffTool] = [
        DiffTool(
            id: "araxis", name: "Araxis Merge", sfSymbol: "rectangle.split.2x1",
            extraArguments: [],
            // Bundle path first: ImageMagick also installs a `compare` on PATH.
            commandCandidates: [
                "/Applications/Araxis Merge.app/Contents/Utilities/compare",
                "/usr/local/bin/compare",
            ]
        ),
        DiffTool(
            id: "kaleidoscope", name: "Kaleidoscope", sfSymbol: "circle.lefthalf.filled",
            extraArguments: [],
            commandCandidates: [
                "/usr/local/bin/ksdiff",
                "/opt/homebrew/bin/ksdiff",
                "/Applications/Kaleidoscope.app/Contents/Resources/bin/ksdiff",
            ]
        ),
        DiffTool(
            id: "bcompare", name: "Beyond Compare", sfSymbol: "arrow.left.arrow.right",
            extraArguments: [],
            commandCandidates: [
                "/usr/local/bin/bcomp",
                "/Applications/Beyond Compare.app/Contents/MacOS/bcomp",
            ]
        ),
        DiffTool(
            id: "vscode", name: "VS Code", sfSymbol: "chevron.left.forwardslash.chevron.right",
            extraArguments: ["--diff"],
            commandCandidates: [
                "/usr/local/bin/code",
                "/opt/homebrew/bin/code",
                "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            ]
        ),
        DiffTool(
            id: "filemerge", name: "FileMerge", sfSymbol: "doc.on.doc",
            extraArguments: [],
            commandCandidates: ["/usr/bin/opendiff"]
        ),
    ]

    static func find(id: String) -> DiffTool? {
        all.first { $0.id == id }
    }

    /// The subset of `all` for which `probe` returns true (probe = "is installed?").
    static func installed(probe: (DiffTool) -> Bool) -> [DiffTool] {
        all.filter(probe)
    }

    /// The tool that should actually be used: the stored choice if it is installed,
    /// otherwise the first installed tool, otherwise nil (nothing installed).
    static func effective(storedID: String?, installed: [DiffTool]) -> DiffTool? {
        installed.first { $0.id == storedID } ?? installed.first
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodegen generate && xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`
Expected: PASS (all `DiffToolTests` green).

- [ ] **Step 5: Lint**

Run: `swiftlint lint`
Expected: no new violations.

- [ ] **Step 6: Commit** *(optional — only if the user asks)*

```bash
git add OhMyWorktree/Models/DiffTool.swift OhMyWorktreeTests/DiffToolTests.swift OhMyWorktree.xcodeproj
git commit -m "feat: add pure DiffTool catalog for external diff hand-off"
```

---

## Task 2: `DiffToolLauncher` (detection + launch, coverage-excluded)

**Files:**
- Create: `OhMyWorktree/Services/DiffToolLauncher.swift`
- Modify: `coverage-exclude.txt`

- [ ] **Step 1: Add the file to the coverage exclude list**

Open `coverage-exclude.txt` and add this line in the Services group (next to `ExternalToolLauncher.swift`):

```
OhMyWorktree/Services/DiffToolLauncher.swift
```

- [ ] **Step 2: Write the implementation**

Create `OhMyWorktree/Services/DiffToolLauncher.swift`:

```swift
import Foundation

/// Detects installed external diff tools and launches one on a file pair.
/// The impure half of the diff-tool feature (filesystem probing + `Process`);
/// the testable catalog/arg logic lives in `DiffTool`. Coverage-excluded.
final class DiffToolLauncher: Sendable {

    private let fileExists: @Sendable (String) -> Bool

    init(fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.fileExists = fileExists
    }

    /// First existing command path for `tool`, or nil if none is present.
    func resolvedCommand(for tool: DiffTool) -> String? {
        tool.commandCandidates.first(where: fileExists)
    }

    func isInstalled(_ tool: DiffTool) -> Bool {
        resolvedCommand(for: tool) != nil
    }

    /// The installed subset of `DiffTool.all`, in catalog order.
    func installedTools() -> [DiffTool] {
        DiffTool.installed { isInstalled($0) }
    }

    /// Launches `tool` to diff `mainPath` (left) against `worktreePath` (right).
    /// Fire-and-forget: diff tools are long-lived GUI apps, so we do not wait.
    func launch(_ tool: DiffTool, mainPath: String, worktreePath: String) throws {
        guard let command = resolvedCommand(for: tool) else {
            throw OhMyWorktreeError.externalToolNotFound(tool: tool.name)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = tool.launchArguments(mainPath: mainPath, worktreePath: worktreePath)
        try process.run()
    }
}
```

- [ ] **Step 3: Regenerate + build**

Run: `xcodegen generate && xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit** *(optional — only if the user asks)*

```bash
git add OhMyWorktree/Services/DiffToolLauncher.swift coverage-exclude.txt OhMyWorktree.xcodeproj
git commit -m "feat: add DiffToolLauncher (detect + launch external diff tools)"
```

---

## Task 3: `DiffToolMenu` picker view

**Files:**
- Create: `OhMyWorktree/Views/Detail/DiffToolMenu.swift`

- [ ] **Step 1: Write the implementation**

Create `OhMyWorktree/Views/Detail/DiffToolMenu.swift`:

```swift
import SwiftUI

/// "Open diffs in [tool ▾]" picker. Lists all five tools; tools not present in
/// `available` are disabled with a "Not installed" hint. The selection persists in
/// `@AppStorage("diffToolID")` and is shared by every placement (detail header,
/// browser header, Settings). Coverage-excluded (Views/**).
struct DiffToolMenu: View {
    /// The installed tools (from `DiffToolLauncher.installedTools()`).
    let available: [DiffTool]

    @AppStorage("diffToolID") private var diffToolID: String = ""

    private var effective: DiffTool? {
        DiffTool.effective(storedID: diffToolID.isEmpty ? nil : diffToolID, installed: available)
    }

    var body: some View {
        Menu {
            ForEach(DiffTool.all) { tool in
                let installed = available.contains(tool)
                Button {
                    diffToolID = tool.id
                } label: {
                    Label {
                        Text(installed ? tool.name : "\(tool.name) — Not installed")
                    } icon: {
                        Image(systemName: tool.sfSymbol)
                    }
                    if tool.id == effective?.id { Image(systemName: "checkmark") }
                }
                .disabled(!installed)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: effective?.sfSymbol ?? "arrow.left.arrow.right")
                    .font(.system(size: 12))
                Text(effective?.name ?? "No diff tool")
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
            .foregroundStyle(OMWColor.labelSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(available.isEmpty)
        .help("Choose the diff tool to open copied files in")
    }
}
```

- [ ] **Step 2: Regenerate + build**

Run: `xcodegen generate && xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED (new view compiles; not yet referenced).

- [ ] **Step 3: Commit** *(optional — only if the user asks)*

```bash
git add OhMyWorktree/Views/Detail/DiffToolMenu.swift OhMyWorktree.xcodeproj
git commit -m "feat: add DiffToolMenu picker view"
```

---

## Task 4: View-model hand-off + remove apply glue

**Files:**
- Modify: `OhMyWorktree/ViewModels/WorktreeListViewModel.swift`
- Modify: `OhMyWorktree/ViewModels/WorktreeListViewModel+ExternalTools.swift`
- Modify: `OhMyWorktree/ViewModels/WorktreeListViewModel+CopiedFiles.swift`

All three are coverage-excluded, so no unit tests; verify by building.

- [ ] **Step 1: Inject `DiffToolLauncher` and drop `pendingApply`**

In `OhMyWorktree/ViewModels/WorktreeListViewModel.swift`:

Delete the `pendingApply` property (around line 36):

```swift
    var pendingApply: CopiedFile?
```

Add a stored launcher next to `let toolLauncher: ExternalToolLauncher` (around line 72):

```swift
    let diffToolLauncher: DiffToolLauncher
```

In `init(...)`, add a defaulted parameter alongside `toolLauncher` (around line 97):

```swift
        diffToolLauncher: DiffToolLauncher = DiffToolLauncher(),
```

And assign it next to `self.toolLauncher = toolLauncher` (around line 104):

```swift
        self.diffToolLauncher = diffToolLauncher
```

- [ ] **Step 2: Add `availableDiffTools` + `openInDiffTool`**

In `OhMyWorktree/ViewModels/WorktreeListViewModel+ExternalTools.swift`, under the
`// MARK: - Tool Availability` section add:

```swift
    var availableDiffTools: [DiffTool] { diffToolLauncher.installedTools() }

    /// Hands `file` off to the user's chosen diff tool, comparing main's copy
    /// (left) against the worktree's copy (right). No-op when nothing is installed.
    func openInDiffTool(_ file: CopiedFile, in worktree: Worktree) async {
        guard let repository else { return }
        let installed = diffToolLauncher.installedTools()
        let storedID = UserDefaults.standard.string(forKey: "diffToolID")
        guard let tool = DiffTool.effective(storedID: storedID, installed: installed) else { return }
        let mainPath = (repository.path as NSString).appendingPathComponent(file.path)
        let worktreePath = (worktree.path as NSString).appendingPathComponent(file.path)
        do {
            try diffToolLauncher.launch(tool, mainPath: mainPath, worktreePath: worktreePath)
            copiedToast = "Opening \((file.path as NSString).lastPathComponent) in \(tool.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 3: Remove the in-app diff/apply glue**

Replace the entire body of `OhMyWorktree/ViewModels/WorktreeListViewModel+CopiedFiles.swift` with:

```swift
import Foundation

// MARK: - Copied-files browser glue
//
// Thin view-model glue for the copied-files browser. Diffs are computed by the
// tested `CopiedFileDiffer`; opening a file hands off to an external diff tool
// (see `openInDiffTool` in WorktreeListViewModel+ExternalTools).

extension WorktreeListViewModel {

    /// Open state for the copied-files browser sheet.
    struct CopiedBrowserState: Equatable {
        var worktree: Worktree
    }

    /// Opens the browser to the full list for `worktree`.
    func browseCopiedFiles(for worktree: Worktree) {
        copiedBrowser = CopiedBrowserState(worktree: worktree)
    }
}
```

(This removes `openCopiedDiff`, `applyCopiedFileToMain`, `applyCopiedFileToWorktree`, and the
`focusedPath` field — the browser no longer drills into an in-app diff.)

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD FAILS — `ContentView`, `CopiedFilesBrowser`, and `CopiedFilesPresentation` still
reference the removed `focusedPath` / `onApply` / `pendingApply`. That is expected; Task 5 fixes the
views. (If you prefer a green boundary here, do Task 5 immediately after — they form one logical change.)

- [ ] **Step 5: Commit** *(optional — only if the user asks, and only after Task 5 builds green)*

---

## Task 5: Rewire views to hand-off; remove in-app diff

**Files:**
- Modify: `OhMyWorktree/Views/Detail/DetailPaneView.swift`
- Modify: `OhMyWorktree/Views/Detail/CopiedFilesSection.swift`
- Modify: `OhMyWorktree/Views/Detail/CopiedFilesBrowser.swift`
- Modify: `OhMyWorktree/Views/Detail/CopiedFileRow.swift`
- Modify: `OhMyWorktree/Views/Detail/CopiedFilesPresentation.swift`
- Modify: `OhMyWorktree/Views/ContentView.swift`
- Delete: `OhMyWorktree/Views/Detail/UnifiedDiffView.swift`

All coverage-excluded; verify by building.

- [ ] **Step 1: `DetailPaneView` — pass tools + hand-off callback**

In `OhMyWorktree/Views/Detail/DetailPaneView.swift` replace the two copied-files inputs (around lines 21-22):

```swift
    var onOpenCopiedDiff: (CopiedFile) -> Void = { _ in }
    var onBrowseCopied: () -> Void = {}
```

with:

```swift
    var availableDiffTools: [DiffTool] = []
    var onOpenInDiffTool: (CopiedFile) -> Void = { _ in }
    var onBrowseCopied: () -> Void = {}
```

And update the `CopiedFilesSection` call (around line 74):

```swift
                CopiedFilesSection(
                    files: copied,
                    availableDiffTools: availableDiffTools,
                    onOpenInDiffTool: onOpenInDiffTool,
                    onBrowseAll: onBrowseCopied
                )
```

- [ ] **Step 2: `CopiedFilesSection` — menu in header, chip → hand-off**

In `OhMyWorktree/Views/Detail/CopiedFilesSection.swift`:

Replace the inputs (lines 7-9):

```swift
    let files: [CopiedFile]
    var onOpenDiff: (CopiedFile) -> Void = { _ in }
    var onBrowseAll: () -> Void = {}
```

with:

```swift
    let files: [CopiedFile]
    var availableDiffTools: [DiffTool] = []
    var onOpenInDiffTool: (CopiedFile) -> Void = { _ in }
    var onBrowseAll: () -> Void = {}
```

Replace the `header` body's trailing `.worktreeinclude` label (lines 55-58) — change:

```swift
            Spacer()
            Text(".worktreeinclude")
                .font(.omwMono(10))
                .foregroundStyle(OMWColor.labelQuaternary)
```

to:

```swift
            Spacer()
            DiffToolMenu(available: availableDiffTools)
```

In `chip(_:)` (lines 67-69) change the action and help text:

```swift
        if file.status.isClickable {
            Button { onOpenInDiffTool(file) } label: { chipLabel(file) }
                .buttonStyle(.plain)
                .help("\(file.path) — open in your diff tool")
```

- [ ] **Step 3: `CopiedFilesBrowser` — drop diff drill-in/apply, add menu, rows hand off**

Replace the whole file `OhMyWorktree/Views/Detail/CopiedFilesBrowser.swift` with:

```swift
import SwiftUI

/// A glass sheet that browses a worktree's copied files: searchable, filterable
/// list. Clicking a changed file hands it off to the selected external diff tool.
struct CopiedFilesBrowser: View {
    let files: [CopiedFile]
    let availableDiffTools: [DiffTool]
    var onOpenInDiffTool: (CopiedFile) -> Void
    var onClose: () -> Void

    @Environment(\.omwAccent) private var accent
    @State private var query = ""
    @State private var changedOnly = false

    private var changedCount: Int { files.filter { $0.status.isChanged }.count }

    private var sorted: [CopiedFile] {
        files.sorted { lhs, rhs in
            lhs.status.sortRank != rhs.status.sortRank
                ? lhs.status.sortRank < rhs.status.sortRank
                : lhs.path < rhs.path
        }
    }

    private var filtered: [CopiedFile] {
        sorted.filter { file in
            (!changedOnly || file.status.isChanged)
                && (query.isEmpty || file.path.lowercased().contains(query.lowercased()))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader
                .padding(.init(top: 16, leading: 18, bottom: 0, trailing: 18))
            listControls
                .padding(.init(top: 12, leading: 18, bottom: 4, trailing: 18))
            fileList
            footer
        }
        .frame(width: 520)
        .frame(maxHeight: 560)
        .glassSheet()
        .tint(accent)
        .onExitCommand { onClose() }
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 7) {
                Text("Copied files").font(.system(size: 14, weight: .bold))
                Text("\(files.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(OMWColor.labelTertiary)
                if changedCount > 0 {
                    Text("· \(changedCount) changed vs. main")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OMWColor.sysOrange)
                }
            }
            Spacer()
            DiffToolMenu(available: availableDiffTools)
        }
    }

    private var listControls: some View {
        HStack(spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(OMWColor.labelTertiary)
                TextField("Filter files…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(OMWColor.controlBg, in: Capsule())
            .overlay(Capsule().strokeBorder(OMWColor.separator, lineWidth: 0.5))

            if changedCount > 0 {
                Button { changedOnly.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: changedOnly ? "checkmark" : "arrow.left.arrow.right").font(.system(size: 12))
                        Text("Changed only").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(changedOnly ? OMWColor.onAccent : OMWColor.labelSecondary)
                    .padding(.horizontal, 11).frame(height: 28)
                    .background(changedOnly ? AnyShapeStyle(accent) : AnyShapeStyle(OMWColor.fillTertiary), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { file in
                    CopiedFileRow(file: file) { onOpenInDiffTool(file) }
                }
                if filtered.isEmpty {
                    Text("No files match \u{201C}\(query)\u{201D}.")
                        .font(.system(size: 13)).foregroundStyle(OMWColor.labelTertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, 26)
                }
            }
            .padding(.init(top: 6, leading: 12, bottom: 12, trailing: 12))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("Click a changed file to open it in your diff tool — edits there touch disk only, never Git.")
                .font(.system(size: 11)).foregroundStyle(OMWColor.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Done", action: onClose)
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.init(top: 12, leading: 18, bottom: 14, trailing: 18))
        .overlay(alignment: .top) { Rectangle().fill(OMWColor.separator).frame(height: 0.5) }
    }
}
```

- [ ] **Step 4: `CopiedFileRow` — external-link affordance**

In `OhMyWorktree/Views/Detail/CopiedFileRow.swift`, change the clickable trailing chevron (lines 29-33):

```swift
            if file.status.isClickable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(OMWColor.labelTertiary)
            }
```

to:

```swift
            if file.status.isClickable {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12))
                    .foregroundStyle(OMWColor.labelTertiary)
            }
```

- [ ] **Step 5: `CopiedFilesPresentation` — drop the apply-confirm alert**

Open `OhMyWorktree/Views/Detail/CopiedFilesPresentation.swift`. Keep the `copiedToast` presentation
(it now shows "Opening … in <tool>"); remove the entire `.confirmationDialog`/`.alert` block driven by
`viewModel.pendingApply` (the block spanning the `presenting: viewModel.pendingApply` usage, its
confirm `Button` that calls `applyCopiedFileToMain`, and the `Button("Cancel", …) { viewModel.pendingApply = nil }`).
After editing, `pendingApply` must not appear anywhere in the file.

Verify with: `grep -n "pendingApply" OhMyWorktree/Views/Detail/CopiedFilesPresentation.swift`
Expected: no matches.

- [ ] **Step 6: `ContentView` — wire hand-off, drop apply wiring**

In `OhMyWorktree/Views/ContentView.swift`, in `worktreeColumns` replace the `onOpenCopiedDiff` input
(lines 159-164) with the diff-tool list + hand-off callback:

```swift
            availableDiffTools: worktreeViewModel.availableDiffTools,
            onOpenInDiffTool: { file in
                if let wt = selectedWorktree {
                    Task { await worktreeViewModel.openInDiffTool(file, in: wt) }
                }
            },
            onBrowseCopied: {
                if let wt = selectedWorktree { worktreeViewModel.browseCopiedFiles(for: wt) }
            }
```

In `modalOverlay`, replace the `CopiedFilesBrowser(...)` construction (lines 256-274) with:

```swift
        } else if let browser = worktreeViewModel.copiedBrowser {
            glassModal {
                CopiedFilesBrowser(
                    files: worktreeViewModel.selectedWorktreeDetail?.copiedFiles ?? [],
                    availableDiffTools: worktreeViewModel.availableDiffTools,
                    onOpenInDiffTool: { file in
                        Task { await worktreeViewModel.openInDiffTool(file, in: browser.worktree) }
                    },
                    onClose: { worktreeViewModel.copiedBrowser = nil }
                )
                .environment(\.omwAccent, accent)
                .id(browser.worktree.id)
            }
        }
```

- [ ] **Step 7: Delete the in-app diff view**

```bash
git rm OhMyWorktree/Views/Detail/UnifiedDiffView.swift
```

(If not committing yet, `rm OhMyWorktree/Views/Detail/UnifiedDiffView.swift` is equivalent for the build.)

- [ ] **Step 8: Regenerate + build**

Run: `xcodegen generate && xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. If the compiler reports a leftover reference to `UnifiedDiffView`,
`onApply`, `onApplyToWorktree`, `focusedPath`, or `pendingApply`, remove it — none should remain.

- [ ] **Step 9: Lint**

Run: `swiftlint lint`
Expected: no new violations.

- [ ] **Step 10: Commit** *(optional — only if the user asks)*

```bash
git add -A
git commit -m "feat: hand copied-file diffs to external tools, remove in-app diff"
```

---

## Task 6: Settings "Diff tool" row

**Files:**
- Modify: `OhMyWorktree/Views/GeneralSettingsView.swift`

- [ ] **Step 1: Add the row**

In `OhMyWorktree/Views/GeneralSettingsView.swift` add a `@State` holding the installed tools (near the
existing `@State private var launchAtLogin`):

```swift
    @State private var installedDiffTools: [DiffTool] = []
```

Add a new `Section` inside the `Form` (after the "Worktree Creation" section):

```swift
            Section("Diff Tool") {
                LabeledContent("Open copied-file diffs in") {
                    DiffToolMenu(available: installedDiffTools)
                }
                Text("Clicking a copied file opens its diff in this tool. Only installed tools can be selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

Populate the list in `.onAppear` (extend the existing closure):

```swift
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            installedDiffTools = DiffToolLauncher().installedTools()
        }
```

- [ ] **Step 2: Regenerate + build**

Run: `xcodegen generate && xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit** *(optional — only if the user asks)*

```bash
git add OhMyWorktree/Views/GeneralSettingsView.swift OhMyWorktree.xcodeproj
git commit -m "feat: add Diff tool picker to General settings"
```

---

## Task 7: Remove `applyToMain`/`applyToWorktree`; full green gate

**Files:**
- Modify: `OhMyWorktree/Services/CopiedFileDiffer.swift`
- Modify: `OhMyWorktreeTests/CopiedFileDifferTests.swift`

`CopiedFileDiffer.swift` is **not** coverage-excluded — it must stay 100%. Removing the two now-unused
methods together with their tests keeps it green.

- [ ] **Step 1: Remove the apply methods**

In `OhMyWorktree/Services/CopiedFileDiffer.swift` delete `applyToMain(_:worktreePath:repositoryPath:)`
and `applyToWorktree(_:worktreePath:repositoryPath:)` (and their doc comments). Keep
`compare(relativePaths:worktreePath:repositoryPath:)`. Update the type doc comment's first line to:

```swift
/// Compares a worktree's copied (`.worktreeinclude`) files against the
/// repository's (main worktree's) copies. Stateless; safe to instantiate per call.
```

- [ ] **Step 2: Remove the apply tests**

In `OhMyWorktreeTests/CopiedFileDifferTests.swift` delete the `// MARK: applyToMain` and
`// MARK: applyToWorktree` sections — every `@Test` from `applyOverwritesExistingMainCopy` through
`applyToWorktreeThrowsWhenMainCopyMissing` (the final closing `}` of the suite stays). Keep all
`compare`/`classify` tests.

Verify with: `grep -nE "applyToMain|applyToWorktree" OhMyWorktreeTests/CopiedFileDifferTests.swift OhMyWorktree/Services/CopiedFileDiffer.swift`
Expected: no matches.

- [ ] **Step 3: Regenerate + run tests**

Run: `xcodegen generate && xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`
Expected: PASS — all suites green, including `DiffToolTests` and the trimmed `CopiedFileDifferTests`.

- [ ] **Step 4: Lint**

Run: `swiftlint lint`
Expected: no violations.

- [ ] **Step 5: Coverage gate**

Run: `scripts/coverage.sh`
Expected: PASS — `DiffTool.swift` at 100%, `CopiedFileDiffer.swift` still 100% (no orphaned
uncovered lines), no non-excluded file below 100%.

- [ ] **Step 6: Commit** *(optional — only if the user asks)*

```bash
git add OhMyWorktree/Services/CopiedFileDiffer.swift OhMyWorktreeTests/CopiedFileDifferTests.swift OhMyWorktree.xcodeproj
git commit -m "refactor: drop unused apply-to-main/worktree copied-file actions"
```

---

## Manual verification (after Task 7)

Build and run the app (`xcodebuild ... -scheme OhMyWorktree build` then launch, or open in Xcode):

1. Select a worktree with copied files → the **Copied files** header shows the `DiffToolMenu`; pick a tool.
2. Click a **modified/new/missing** chip → the file opens in the chosen tool (main vs worktree).
3. An **identical** chip is not clickable.
4. **View all** → the browser header has the same menu; clicking a row opens the tool; search +
   "Changed only" still work.
5. **Settings → General → Diff tool** → selecting a tool here changes the default everywhere; not-installed
   tools are disabled with "Not installed".
6. With no diff tool installed, the menu reads "No diff tool" and chips are non-clickable.
7. Confirm the old in-app diff view and "Apply to main" / "Copy to worktree" buttons are gone.

---

## Self-review notes (author check)

- **Spec coverage:** picker in 3 places → Tasks 5 (detail + browser) & 6 (settings); persistence
  `@AppStorage("diffToolID")` → Task 3/4; 5 tools + launch matrix → Task 1; detection/launch → Task 2;
  click → hand-off → Tasks 4-5; removal of in-app diff/apply → Tasks 4, 5, 7; missing/new edge cases →
  handled uniformly by `openInDiffTool`; no-tool / uninstalled fallback → `DiffTool.effective` + menu
  disabled state; coverage strategy → pure model tested (Task 1), impure excluded (Task 2). All spec
  sections map to a task.
- **Type consistency:** `availableDiffTools: [DiffTool]` and `onOpenInDiffTool: (CopiedFile) -> Void`
  used identically across `DetailPaneView`, `CopiedFilesSection`, `CopiedFilesBrowser`, `ContentView`;
  `DiffTool.effective(storedID:installed:)` signature matches every call site (view-model + menu);
  `@AppStorage("diffToolID")` key string identical in `DiffToolMenu` and the VM's `UserDefaults` read.
- **No placeholders:** every code step shows full code or an exact old→new hunk.
