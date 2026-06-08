import SwiftUI

extension View {
    /// Applies the Liquid-Glass backing for Settings and New Worktree sheets.
    func glassSheet() -> some View {
        self
            .background {
                GlassSheetBackground()
            }
            .clipShape(GlassSheetShape())
            .overlay {
                GlassSheetShape().strokeBorder(OMWColor.separator, lineWidth: GlassSheetMetrics.hairlineWidth)
            }
            .presentationBackground(.clear)
    }
}

private struct GlassSheetShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: GlassSheetMetrics.cornerRadius, style: .continuous)
            .inset(by: insetAmount)
            .path(in: rect)
    }

    func inset(by amount: CGFloat) -> GlassSheetShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private struct GlassSheetBackground: View {
    var body: some View {
        GlassSheetShape()
            .fill(OMWColor.glassSheetTint)
            .glassEffect(.regular, in: GlassSheetShape().inset(by: GlassSheetMetrics.glassMaterialInset))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(OMWColor.glassHighlight)
                    .frame(height: GlassSheetMetrics.topHighlightHeight)
                    .padding(.horizontal, GlassSheetMetrics.topHighlightHorizontalInset)
                    .padding(.top, GlassSheetMetrics.topHighlightVerticalInset)
            }
    }
}
