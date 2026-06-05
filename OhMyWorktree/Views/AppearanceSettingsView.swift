import AppKit
import SwiftUI

/// Settings → Appearance: window theme (Auto / Light / Dark) + accent color.
/// Both are persisted via @AppStorage and applied live.
struct AppearanceSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.default.rawValue
    @AppStorage("accentColorName") private var accentColorName = AccentChoice.default.rawValue

    private var mode: AppearanceMode { AppearanceMode.named(appearanceModeRaw) }
    private var accent: AccentChoice { AccentChoice.named(accentColorName) }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceModeRaw) {
                    Label("Auto", systemImage: "circle.lefthalf.filled").tag(AppearanceMode.auto.rawValue)
                    Label("Light", systemImage: "sun.max").tag(AppearanceMode.light.rawValue)
                    Label("Dark", systemImage: "moon").tag(AppearanceMode.dark.rawValue)
                }
                .pickerStyle(.segmented)
                Text(appearanceSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Accent Color") {
                HStack(spacing: 10) {
                    ForEach(AccentChoice.allCases) { choice in
                        accentDot(choice)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
                Text("Tints selection, switches, and focus. \(accent.rawValue) · \(mode.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(accent.color)
        .onChange(of: appearanceModeRaw) { _, _ in applyAppearance() }
        .onAppear { applyAppearance() }
    }

    private func accentDot(_ choice: AccentChoice) -> some View {
        let isSelected = choice == accent
        return Button {
            accentColorName = choice.rawValue
        } label: {
            Circle()
                .fill(choice.color)
                .frame(width: 22, height: 22)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(choice.color, lineWidth: 2).padding(-3)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(choice.rawValue)
    }

    private var appearanceSubtitle: String {
        switch mode {
        case .auto: "Auto — follows your macOS system setting."
        case .light: "Always use the light appearance."
        case .dark: "Always use the dark appearance."
        }
    }

    private func applyAppearance() {
        NSApp.appearance = mode.nsAppearance
    }
}
