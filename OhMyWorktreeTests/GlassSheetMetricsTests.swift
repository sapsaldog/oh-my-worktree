import SwiftUI
import Testing

@testable import OhMyWorktree

@Suite
struct GlassSheetMetricsTests {

    @Test func topHighlightStaysInsideRoundedCorners() {
        #expect(GlassSheetMetrics.topHighlightHorizontalInset >= GlassSheetMetrics.cornerRadius)
        #expect(GlassSheetMetrics.topHighlightVerticalInset >= GlassSheetMetrics.hairlineWidth)
    }

    @Test func glassMaterialDoesNotShareTheOuterAntialiasedEdge() {
        #expect(GlassSheetMetrics.glassMaterialInset >= GlassSheetMetrics.hairlineWidth)
    }

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

    @Test func glassPopoverModifierIsAvailableForCompactPresentedSurfaces() {
        let view = Text("Popover").glassPopover()
        #expect(String(describing: type(of: view)).isEmpty == false)
    }
}
