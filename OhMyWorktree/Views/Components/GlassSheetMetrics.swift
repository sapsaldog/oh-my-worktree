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
