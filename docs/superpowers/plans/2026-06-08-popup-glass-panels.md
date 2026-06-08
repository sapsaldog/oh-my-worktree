# Popup Glass Panels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved stronger Liquid Glass style to custom sheets and popovers, and move Import PR off native macOS sheet presentation so it can share the same translucent glass panel.

**Architecture:** Keep the visual treatment centralized in `GlassSheet.swift` and `GlassSheetMetrics.swift`. `ContentView` remains the owner of app-level modal overlays, while individual popover call sites opt into a new `glassPopover()` modifier inside their existing `.popover` closures.

**Tech Stack:** Swift 5.9, SwiftUI on macOS 26, Swift Testing, existing `OMWColor`/`OMWRadius` design tokens.

---

## File Structure

- Modify `OhMyWorktree/Views/Components/GlassSheetMetrics.swift`: add testable metrics for stronger modal scrim and popover glass geometry.
- Modify `OhMyWorktree/Views/Components/GlassSheet.swift`: refactor the sheet-only implementation into a shared glass panel implementation with `glassSheet()` and `glassPopover()`.
- Modify `OhMyWorktree/Views/Theme/OMWTheme.swift`: lower sheet tint alpha, add popover tint, and strengthen highlight alpha.
- Modify `OhMyWorktree/Views/ContentView.swift`: remove native Import PR `.sheet` and present Import PR through `modalOverlay` with the shared custom glass backing.
- Modify `OhMyWorktree/Views/ImportPRView.swift`: add an optional close callback, use it for Cancel and successful import, set stable overlay dimensions, and apply `glassSheet()`.
- Modify `OhMyWorktree/Views/Sheets/CreateWorktreeSheet.swift`: apply `glassPopover()` to the branch picker popover content.
- Modify `OhMyWorktree/Views/MainWindow/WindowStatusBar.swift`: apply `glassPopover()` to the background tasks popover.
- Modify `OhMyWorktree/Views/QueueStatusBarView.swift`: apply `glassPopover()` to the queue detail popover.
- Modify `OhMyWorktree/Views/RepositorySelectorView.swift`: apply `glassPopover()` to the repository settings popover.
- Modify `OhMyWorktreeTests/GlassSheetMetricsTests.swift`: add focused tests for the new shared metrics.

### Task 1: Stronger Shared Glass Metrics

**Files:**
- Modify: `OhMyWorktreeTests/GlassSheetMetricsTests.swift`
- Modify: `OhMyWorktree/Views/Components/GlassSheetMetrics.swift`
- Modify: `OhMyWorktree/Views/Theme/OMWTheme.swift`

- [ ] **Step 1: Write failing metric tests**

Add these tests to `OhMyWorktreeTests/GlassSheetMetricsTests.swift`:

```swift
    @Test func modalScrimIsWeakEnoughForBackgroundToReadThrough() {
        #expect(GlassSheetMetrics.modalScrimOpacity < 0.40)
        #expect(GlassSheetMetrics.modalScrimOpacity > 0.20)
    }

    @Test func popoverGlassUsesCompactRoundingInsideSheetRounding() {
        #expect(GlassSheetMetrics.popoverCornerRadius < GlassSheetMetrics.cornerRadius)
        #expect(GlassSheetMetrics.popoverCornerRadius >= OMWRadius.lg)
        #expect(GlassSheetMetrics.popoverTopHighlightHorizontalInset >= GlassSheetMetrics.popoverCornerRadius)
    }

    @Test func popoverGlassMaterialDoesNotShareTheOuterAntialiasedEdge() {
        #expect(GlassSheetMetrics.popoverGlassMaterialInset >= GlassSheetMetrics.hairlineWidth)
    }
```

- [ ] **Step 2: Run metric tests to verify RED**

Run:

```bash
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test -only-testing:OhMyWorktreeTests/GlassSheetMetricsTests
```

Expected: FAIL because `modalScrimOpacity`, `popoverCornerRadius`, `popoverTopHighlightHorizontalInset`, and `popoverGlassMaterialInset` do not exist yet.

- [ ] **Step 3: Add minimal metrics**

Update `OhMyWorktree/Views/Components/GlassSheetMetrics.swift` to:

```swift
import SwiftUI

enum GlassSheetMetrics {
    static let cornerRadius: CGFloat = OMWRadius.xxl
    static let popoverCornerRadius: CGFloat = OMWRadius.xl
    static let hairlineWidth: CGFloat = 0.5
    static let glassMaterialInset: CGFloat = hairlineWidth
    static let popoverGlassMaterialInset: CGFloat = hairlineWidth
    static let topHighlightHeight: CGFloat = 1
    static let topHighlightHorizontalInset: CGFloat = cornerRadius
    static let popoverTopHighlightHorizontalInset: CGFloat = popoverCornerRadius
    static let topHighlightVerticalInset: CGFloat = hairlineWidth
    static let modalScrimOpacity: Double = 0.32
}
```

Update the glass color section of `OhMyWorktree/Views/Theme/OMWTheme.swift` to:

```swift
    /// Thin tint over native sheet glass. Kept low so the parent window's
    /// selection colors and columns read through the stronger glass blur.
    static let glassSheetTint = dynamic(light: (255, 255, 255, 0.46), dark: (34, 34, 36, 0.46))
    /// Compact popover tint using the same stronger Liquid Glass direction.
    static let glassPopoverTint = dynamic(light: (255, 255, 255, 0.50), dark: (34, 34, 36, 0.50))
    /// Top inner sheen on Liquid-Glass surfaces (`--glass-highlight`): a 1px white
    /// line along the upper edge of sheets/popovers that sells the glass rim.
    static let glassHighlight = dynamic(light: (255, 255, 255, 0.72), dark: (255, 255, 255, 0.22))
```

- [ ] **Step 4: Run metric tests to verify GREEN**

Run:

```bash
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test -only-testing:OhMyWorktreeTests/GlassSheetMetricsTests
```

Expected: PASS for `GlassSheetMetricsTests`.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add OhMyWorktreeTests/GlassSheetMetricsTests.swift OhMyWorktree/Views/Components/GlassSheetMetrics.swift OhMyWorktree/Views/Theme/OMWTheme.swift
git commit -m "Tune stronger glass panel metrics"
```

### Task 2: Shared Glass Panel Modifier

**Files:**
- Modify: `OhMyWorktree/Views/Components/GlassSheet.swift`
- Test: `OhMyWorktreeTests/GlassSheetMetricsTests.swift`

- [ ] **Step 1: Write failing API availability test for popover glass**

Add `import SwiftUI` to `OhMyWorktreeTests/GlassSheetMetricsTests.swift`, then add this test:

```swift
    @Test func glassPopoverModifierIsAvailableForCompactPresentedSurfaces() {
        let view = Text("Popover").glassPopover()
        #expect(String(describing: type(of: view)).isEmpty == false)
    }
```

- [ ] **Step 2: Run metric tests to verify RED**

Run:

```bash
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test -only-testing:OhMyWorktreeTests/GlassSheetMetricsTests
```

Expected: FAIL to compile with `Value of type 'Text' has no member 'glassPopover'`.

- [ ] **Step 3: Refactor `GlassSheet.swift` into shared sheet/popover implementation**

Replace `OhMyWorktree/Views/Components/GlassSheet.swift` with:

```swift
import SwiftUI

extension View {
    /// Applies the Liquid-Glass backing for Settings, New Worktree, and Import PR sheets.
    func glassSheet() -> some View {
        glassPanel(kind: .sheet)
            .presentationBackground(.clear)
    }

    /// Applies the compact Liquid-Glass backing for popovers.
    func glassPopover() -> some View {
        glassPanel(kind: .popover)
            .presentationBackground(.clear)
    }

    private func glassPanel(kind: GlassPanelKind) -> some View {
        self
            .background {
                GlassPanelBackground(kind: kind)
            }
            .clipShape(GlassPanelShape(cornerRadius: kind.cornerRadius))
            .overlay {
                GlassPanelShape(cornerRadius: kind.cornerRadius)
                    .strokeBorder(OMWColor.separator, lineWidth: GlassSheetMetrics.hairlineWidth)
            }
    }
}

private enum GlassPanelKind {
    case sheet
    case popover

    var cornerRadius: CGFloat {
        switch self {
        case .sheet: GlassSheetMetrics.cornerRadius
        case .popover: GlassSheetMetrics.popoverCornerRadius
        }
    }

    var materialInset: CGFloat {
        switch self {
        case .sheet: GlassSheetMetrics.glassMaterialInset
        case .popover: GlassSheetMetrics.popoverGlassMaterialInset
        }
    }

    var topHighlightHorizontalInset: CGFloat {
        switch self {
        case .sheet: GlassSheetMetrics.topHighlightHorizontalInset
        case .popover: GlassSheetMetrics.popoverTopHighlightHorizontalInset
        }
    }

    var tint: Color {
        switch self {
        case .sheet: OMWColor.glassSheetTint
        case .popover: OMWColor.glassPopoverTint
        }
    }
}

private struct GlassPanelShape: InsettableShape {
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .inset(by: insetAmount)
            .path(in: rect)
    }

    func inset(by amount: CGFloat) -> GlassPanelShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private struct GlassPanelBackground: View {
    var kind: GlassPanelKind

    var body: some View {
        let shape = GlassPanelShape(cornerRadius: kind.cornerRadius)

        shape
            .fill(kind.tint)
            .glassEffect(.regular, in: shape.inset(by: kind.materialInset))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(OMWColor.glassHighlight)
                    .frame(height: GlassSheetMetrics.topHighlightHeight)
                    .padding(.horizontal, kind.topHighlightHorizontalInset)
                    .padding(.top, GlassSheetMetrics.topHighlightVerticalInset)
            }
    }
}
```

- [ ] **Step 4: Run metric tests and build**

Run:

```bash
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test -only-testing:OhMyWorktreeTests/GlassSheetMetricsTests
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build
```

Expected: metric tests PASS and app target builds.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add OhMyWorktreeTests/GlassSheetMetricsTests.swift OhMyWorktree/Views/Components/GlassSheet.swift
git commit -m "Share glass panel styling with popovers"
```

### Task 3: Import PR Custom Glass Overlay

**Files:**
- Modify: `OhMyWorktree/Views/ContentView.swift`
- Modify: `OhMyWorktree/Views/ImportPRView.swift`
- Test: `OhMyWorktreeTests/AppDelegateColdStartTests.swift`

- [ ] **Step 1: Add a failing overlay initializer test**

Add this test after `importPRSetsSheetFlag()` in `OhMyWorktreeTests/AppDelegateColdStartTests.swift`:

```swift
    @Test func importPRViewAcceptsOverlayDismissCallback() {
        let worktreeVM = WorktreeListViewModel()
        _ = ImportPRView(worktreeViewModel: worktreeVM, onDismiss: {})
    }
```

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test -only-testing:OhMyWorktreeTests/AppDelegateColdStartTests/importPRViewAcceptsOverlayDismissCallback
```

Expected: FAIL to compile with `Extra argument 'onDismiss' in call`.

- [ ] **Step 3: Convert ContentView from native sheet to custom overlay**

In `OhMyWorktree/Views/ContentView.swift`, delete this modifier from `body`:

```swift
        .sheet(isPresented: $worktreeViewModel.isShowingImportPR) {
            ImportPRView(worktreeViewModel: worktreeViewModel)
        }
```

Then update `modalOverlay` to:

```swift
    @ViewBuilder
    private var modalOverlay: some View {
        if worktreeViewModel.isShowingCreateSheet {
            glassModal {
                CreateWorktreeSheet(
                    worktreeViewModel: worktreeViewModel,
                    repoName: repoViewModel.selectedRepository?.name ?? "this repository",
                    onDismiss: { worktreeViewModel.isShowingCreateSheet = false }
                )
                .environment(\.omwAccent, accent)
            }
        } else if worktreeViewModel.isShowingImportPR {
            glassModal {
                ImportPRView(
                    worktreeViewModel: worktreeViewModel,
                    onDismiss: { worktreeViewModel.isShowingImportPR = false }
                )
                .environment(\.omwAccent, accent)
            }
        } else if worktreeViewModel.isShowingSettings {
            glassModal {
                settingsSheet
            }
        }
    }
```

Finally update the scrim inside `glassModal` to:

```swift
            Color.black.opacity(GlassSheetMetrics.modalScrimOpacity)
```

- [ ] **Step 4: Add close callback and glass backing to ImportPRView**

In `OhMyWorktree/Views/ImportPRView.swift`, change the top of `ImportPRView` to:

```swift
struct ImportPRView: View {
    var worktreeViewModel: WorktreeListViewModel
    var onDismiss: (() -> Void)?

    @State private var viewModel = ImportPRViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: Int?

    var body: some View {
        VStack(spacing: 0) {
            headerArea
            Divider()
            contentArea
            Divider()
            footerArea
        }
        .frame(width: 700, height: 480)
        .glassSheet()
        .onAppear {
            viewModel.repositoryPath = worktreeViewModel.repository?.path ?? ""
            viewModel.repositoryName = worktreeViewModel.repository?.name ?? ""
            Task { await viewModel.loadPRs() }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
```

Add this helper inside `ImportPRView`:

```swift
    private func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
```

Update `footerArea` to pass the close callback:

```swift
    private var footerArea: some View {
        FooterAreaView(
            viewModel: viewModel,
            worktreeViewModel: worktreeViewModel,
            onDismiss: close
        )
    }
```

Update `FooterAreaView` to:

```swift
private struct FooterAreaView: View {
    var viewModel: ImportPRViewModel
    var worktreeViewModel: WorktreeListViewModel
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Button("Cancel", action: onDismiss)
                .keyboardShortcut(.cancelAction)

            Button("Import Worktree") {
                guard let pr = viewModel.selectedPR else { return }
                if let error = worktreeViewModel.addWorktreeFromPR(pr) {
                    viewModel.errorMessage = error
                } else {
                    onDismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.selectedPR == nil)
        }
        .padding(16)
    }
}
```

- [ ] **Step 5: Run focused tests and build**

Run:

```bash
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test -only-testing:OhMyWorktreeTests/AppDelegateColdStartTests/importPRSetsSheetFlag -only-testing:OhMyWorktreeTests/AppDelegateColdStartTests/importPRViewAcceptsOverlayDismissCallback
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build
```

Expected: focused tests PASS and app target builds.

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add OhMyWorktreeTests/AppDelegateColdStartTests.swift OhMyWorktree/Views/ContentView.swift OhMyWorktree/Views/ImportPRView.swift
git commit -m "Present Import PR with glass overlay"
```

### Task 4: Apply Glass Popovers

**Files:**
- Modify: `OhMyWorktree/Views/Sheets/CreateWorktreeSheet.swift`
- Modify: `OhMyWorktree/Views/MainWindow/WindowStatusBar.swift`
- Modify: `OhMyWorktree/Views/QueueStatusBarView.swift`
- Modify: `OhMyWorktree/Views/RepositorySelectorView.swift`
- Test: `OhMyWorktreeTests/GlassSheetMetricsTests.swift`

- [ ] **Step 1: Run a failing static coverage check for popover call sites**

Run:

```bash
for file in \
  OhMyWorktree/Views/Sheets/CreateWorktreeSheet.swift \
  OhMyWorktree/Views/MainWindow/WindowStatusBar.swift \
  OhMyWorktree/Views/QueueStatusBarView.swift \
  OhMyWorktree/Views/RepositorySelectorView.swift
do
  rg -q "glassPopover\\(\\)" "$file"
done
```

Expected: FAIL because these popover call sites do not all use `glassPopover()` yet.

- [ ] **Step 2: Add a regression test for popover radius hierarchy**

Add this test to `OhMyWorktreeTests/GlassSheetMetricsTests.swift`:

```swift
    @Test func popoverRadiusRemainsLargeEnoughForLiquidGlassRim() {
        #expect(GlassSheetMetrics.popoverCornerRadius >= OMWRadius.xl)
        #expect(GlassSheetMetrics.topHighlightHeight == 1)
    }
```

- [ ] **Step 3: Run metric tests**

Run:

```bash
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test -only-testing:OhMyWorktreeTests/GlassSheetMetricsTests
```

Expected: PASS. This locks the compact popover geometry before applying it to all popover call sites.

- [ ] **Step 4: Apply glassPopover to branch picker**

In `OhMyWorktree/Views/Sheets/CreateWorktreeSheet.swift`, update `branchPickerPopover` to end with:

```swift
        .frame(width: 260)
        .glassPopover()
        .onAppear { branchFilterFocused = true }
```

- [ ] **Step 5: Apply glassPopover to background task popover**

In `OhMyWorktree/Views/MainWindow/WindowStatusBar.swift`, update the `.popover` content to:

```swift
            BackgroundTasksPopover(
                running: running,
                failed: failed,
                onSelect: { job in worktreeViewModel.selectedWorktreeIDs = [job.worktreeID]; showTasks = false },
                onRetry: { job in worktreeViewModel.jobQueue.retry(job.id) },
                onClear: { worktreeViewModel.jobQueue.clearFailed(); showTasks = false }
            )
            .glassPopover()
```

- [ ] **Step 6: Apply glassPopover to queue detail popover**

In `OhMyWorktree/Views/QueueStatusBarView.swift`, update the `.popover` content to:

```swift
            QueueDetailPopoverView(queue: queue)
                .glassPopover()
```

- [ ] **Step 7: Apply glassPopover to repository settings popover**

In `OhMyWorktree/Views/RepositorySelectorView.swift`, update the repository settings popover content to:

```swift
                    if let repo = viewModel.selectedRepository {
                        RepositorySettingsView(
                            repository: repo,
                            store: viewModel.store
                        )
                        .glassPopover()
                    }
```

- [ ] **Step 8: Run static coverage check, build, and focused tests**

Run:

```bash
for file in \
  OhMyWorktree/Views/Sheets/CreateWorktreeSheet.swift \
  OhMyWorktree/Views/MainWindow/WindowStatusBar.swift \
  OhMyWorktree/Views/QueueStatusBarView.swift \
  OhMyWorktree/Views/RepositorySelectorView.swift
do
  rg -q "glassPopover\\(\\)" "$file"
done
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test -only-testing:OhMyWorktreeTests/GlassSheetMetricsTests
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktree -destination 'platform=macOS' build
```

Expected: static coverage check exits 0, metric tests PASS, and app target builds.

- [ ] **Step 9: Commit Task 4**

Run:

```bash
git add OhMyWorktreeTests/GlassSheetMetricsTests.swift OhMyWorktree/Views/Sheets/CreateWorktreeSheet.swift OhMyWorktree/Views/MainWindow/WindowStatusBar.swift OhMyWorktree/Views/QueueStatusBarView.swift OhMyWorktree/Views/RepositorySelectorView.swift
git commit -m "Apply glass styling to popovers"
```

### Task 5: Full Verification

**Files:**
- Verify all modified files

- [ ] **Step 1: Run SwiftLint**

Run:

```bash
swiftlint lint
```

Expected: `Done linting! Found 0 violations, 0 serious`.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Manual app visual check**

Run the app from Xcode or the built debug product and verify:

- Settings, New Worktree, and Import PR use the stronger B-style glass.
- Import PR appears as an app-owned overlay, not a native macOS sheet.
- The modal scrim is lighter than before and the worktree list reads through the panel.
- Branch picker, background tasks, queue detail, and repository settings popovers use the compact glass panel.
- Text remains legible in dark and light appearance.

- [ ] **Step 4: Commit any verification-only follow-up fixes**

If verification required code changes, run:

```bash
git add OhMyWorktree OhMyWorktreeTests
git commit -m "Polish popup glass verification fixes"
```

Expected: no commit is needed if verification found no follow-up fixes.
