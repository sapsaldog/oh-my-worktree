import SwiftUI

/// A dev-tool app icon as a unified bordered rounded-square chip (`.ab-tile`):
/// the prototype's bundled `tool-{id}` icon, muted to grayscale (per v5).
/// Tile 34×34 r9, icon 26, `grayscale(1) contrast(0.95) opacity 0.85`.
struct ToolIcon: View {
    /// Tool id matching a `tool-{id}` image asset (iterm/ghostty/cmux/vscode/cursor).
    let toolID: String

    var body: some View {
        Image("tool-\(toolID)")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 26, height: 26)
            .grayscale(1)
            .contrast(0.95)
            .opacity(0.85)
            .frame(width: 34, height: 34)
            .background(OMWColor.controlBg, in: RoundedRectangle(cornerRadius: 9))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(OMWColor.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
    }
}
