# Popup Glass Panels Design

## Context

Oh My Worktree already has a reusable `glassSheet()` modifier used by the custom Settings and New Worktree overlays. The current visual direction is too close to a dark translucent plate: the dimming layer and sheet tint reduce how much of the worktree UI reads through the popup.

The app also still has popup surfaces that do not share the same glass treatment:

- `ImportPRView` is presented with SwiftUI `.sheet`.
- Branch picking, background tasks, queue details, and repository settings use SwiftUI `.popover`.
- Alerts are system-owned SwiftUI/NSAlert presentations and are outside the custom glass panel scope.

Apple's SwiftUI `presentationBackground` documentation notes that macOS sheet presentations do not support transparent sheet backgrounds, so custom overlays are the reliable path for sheet-like surfaces that must visually reveal the parent window behind them.

## Approved Direction

Use the visual option B: stronger Liquid Glass.

The design should make popups feel more translucent and glass-like without making dense controls hard to read:

- Lower the dark sheet tint so the parent window reads through more clearly.
- Keep or increase the blur/glass effect to preserve separation and legibility.
- Strengthen the top rim highlight and border enough to make the panel edge feel like glass.
- Reduce the modal scrim opacity so the background does not collapse into a dark flat layer.
- Apply the shared glass panel style consistently to custom sheets and popovers.

## Scope

In scope:

- Tune shared glass tokens and metrics used by `glassSheet()`.
- Add a reusable glass popover modifier if the existing sheet modifier is not flexible enough for small popovers.
- Convert Import PR from a native SwiftUI `.sheet` to the same custom overlay pattern used by Settings and New Worktree, preserving dismissal behavior and keyboard shortcuts.
- Apply glass styling to custom popover content for branch selection, background tasks, queue details, and repository settings.
- Keep system alerts as native alerts; replacing them with app-owned confirmation overlays is explicitly separate future work.
- Update focused tests for shared glass metrics and any presentation state behavior touched by the conversion.

Out of scope:

- Replacing all SwiftUI alerts/confirmation dialogs with custom dialogs.
- Redesigning popup content layout beyond changes needed for glass legibility.
- Changing app navigation or repository/worktree data flow.

## Implementation Notes

Use existing SwiftUI patterns and design tokens. Keep changes centralized so future popup surfaces can opt into the same appearance with one modifier.

The likely implementation shape:

- Adjust `OMWColor.glassSheetTint`, `OMWColor.glassHighlight`, and related shared metrics.
- Extend `GlassSheet` with a popover-appropriate variant, or make the modifier configurable by size/context.
- Add Import PR to `ContentView.modalOverlay` with the same `glassModal` backing used by other custom sheets.
- Apply the popover variant inside each `.popover` content closure.
- Avoid changing native system alert presentation in this pass.

## Verification

Run:

- `swiftlint lint`
- `xcodebuild -project OhMyWorktree.xcodeproj -scheme OhMyWorktreeTests -destination 'platform=macOS' test`

Manual visual checks:

- Settings and New Worktree still have rounded, seamless glass corners.
- Import PR uses the same stronger glass and shows the parent window through it.
- Branch picker, background-task popovers, queue detail popover, and repository settings popover share the glass panel treatment.
- Text and buttons remain legible in dark and light appearance.
