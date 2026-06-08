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
}
