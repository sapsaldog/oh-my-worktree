import AppKit
import SwiftUI
import Testing

@testable import OhMyWorktree

@Suite
struct AccentChoiceTests {

    @Test func allCasesOrderMatchesSwatchRow() {
        #expect(AccentChoice.allCases == [.graphite, .blue, .purple, .green, .orange, .pink])
    }

    @Test func defaultIsBlue() {
        #expect(AccentChoice.default == .blue)
    }

    @Test func identifierIsRawName() {
        #expect(AccentChoice.purple.id == "Purple")
        #expect(AccentChoice.graphite.id == "Graphite")
    }

    @Test func rgbValuesMatchDesign() {
        #expect(AccentChoice.graphite.rgb == (94, 94, 98))
        #expect(AccentChoice.blue.rgb == (0, 122, 255))
        #expect(AccentChoice.purple.rgb == (124, 58, 237))
        #expect(AccentChoice.green.rgb == (52, 199, 89))
        #expect(AccentChoice.orange.rgb == (255, 149, 0))
        #expect(AccentChoice.pink.rgb == (255, 45, 85))
    }

    @Test func namedResolvesKnownValues() {
        #expect(AccentChoice.named("Blue") == .blue)
        #expect(AccentChoice.named("Graphite") == .graphite)
        #expect(AccentChoice.named("Pink") == .pink)
    }

    @Test func namedFallsBackToDefault() {
        #expect(AccentChoice.named(nil) == .blue)
        #expect(AccentChoice.named("Chartreuse") == .blue)
        #expect(AccentChoice.named("") == .blue)
    }

    @Test func colorMatchesRGBComponents() throws {
        for choice in AccentChoice.allCases {
            let resolved = try #require(NSColor(choice.color).usingColorSpace(.sRGB))
            #expect(abs(Double(resolved.redComponent) - Double(choice.rgb.red) / 255) < 0.01)
            #expect(abs(Double(resolved.greenComponent) - Double(choice.rgb.green) / 255) < 0.01)
            #expect(abs(Double(resolved.blueComponent) - Double(choice.rgb.blue) / 255) < 0.01)
        }
    }
}
