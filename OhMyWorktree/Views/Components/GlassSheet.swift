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
