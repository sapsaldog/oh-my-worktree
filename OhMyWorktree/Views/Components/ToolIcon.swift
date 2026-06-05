import AppKit
import SwiftUI

/// A dev-tool icon as a unified bordered rounded-square chip (`.ab-tile`): the
/// real installed app icon, muted to grayscale (per v5). Falls back to an SF
/// Symbol when the app can't be resolved (e.g. a CLI-only tool).
struct ToolIcon: View {
    let bundleID: String?
    let fallbackSystemImage: String

    var body: some View {
        Group {
            if let icon = Self.resolve(bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .grayscale(1)
                    .contrast(0.95)
                    .opacity(0.85)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(OMWColor.labelSecondary)
            }
        }
        .frame(width: 19, height: 19)
        .frame(width: 34, height: 34)
        .background(OMWColor.controlBg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(OMWColor.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
    }

    static func resolve(_ bundleID: String?) -> NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
