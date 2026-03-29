import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject var shortcutManager: ShortcutManager
    @AppStorage("globalHotkeyEnabled") private var globalHotkeyEnabled = true

    var body: some View {
        Form {
            Section("Global Hotkey") {
                Toggle("Enable global hotkey", isOn: $globalHotkeyEnabled)
                    .onChange(of: globalHotkeyEnabled) { _, newValue in
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.hotkeyManager.setEnabled(newValue)
                            if newValue {
                                appDelegate.setupGlobalHotkey()
                            }
                        }
                    }

                HotkeyRecorderView(action: .globalHotkey, shortcutManager: shortcutManager)

                Text("Press the global hotkey to toggle the menu bar popup from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("In-App Shortcuts") {
                ForEach(inAppActions, id: \.self) { action in
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

    private var inAppActions: [ShortcutAction] {
        ShortcutAction.allCases.filter { !$0.isGlobal }
    }
}
