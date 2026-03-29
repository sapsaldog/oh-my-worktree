import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject var shortcutManager: ShortcutManager
    @AppStorage("globalHotkeyEnabled") private var globalHotkeyEnabled = true

    var body: some View {
        Form {
            Section("Global Hotkey") {
                Toggle("Enable global hotkey", isOn: $globalHotkeyEnabled)
                    .onChange(of: globalHotkeyEnabled) { _, _ in
                        shortcutManager.notifySettingsChanged()
                    }

                HotkeyRecorderView(action: .globalHotkey, shortcutManager: shortcutManager)

                Text("Press the global hotkey to toggle the menu bar popup from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("In-App Shortcuts") {
                ForEach(Self.inAppActions, id: \.self) { action in
                    HotkeyRecorderView(action: action, shortcutManager: shortcutManager)
                }
            }

            Section {
                Button("Reset All to Defaults") {
                    shortcutManager.resetAllToDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let inAppActions = ShortcutAction.allCases.filter { !$0.isGlobal }
}
