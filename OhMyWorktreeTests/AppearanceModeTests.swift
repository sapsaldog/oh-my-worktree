import AppKit
import Testing

@testable import OhMyWorktree

@Suite
struct AppearanceModeTests {

    @Test func allCasesOrderMatchesSegmentedControl() {
        #expect(AppearanceMode.allCases == [.auto, .light, .dark])
    }

    @Test func defaultIsAuto() {
        #expect(AppearanceMode.default == .auto)
    }

    @Test func identifierIsRawValue() {
        #expect(AppearanceMode.dark.id == "dark")
    }

    @Test func nsAppearanceMapping() {
        #expect(AppearanceMode.auto.nsAppearance == nil)
        #expect(AppearanceMode.light.nsAppearance?.name == .aqua)
        #expect(AppearanceMode.dark.nsAppearance?.name == .darkAqua)
    }

    @Test func namedResolvesKnownAndFallsBack() {
        #expect(AppearanceMode.named("light") == .light)
        #expect(AppearanceMode.named("dark") == .dark)
        #expect(AppearanceMode.named(nil) == .auto)
        #expect(AppearanceMode.named("bogus") == .auto)
    }
}
