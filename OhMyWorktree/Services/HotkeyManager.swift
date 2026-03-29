import AppKit
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.ohmyworktree", category: "HotkeyManager")

// MARK: - KeyCombo

/// Represents a keyboard shortcut combination (modifier flags + key code).
struct KeyCombo: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    /// Parses a human-readable shortcut string like "⌥⇧W" into a `KeyCombo`.
    /// Requires at least one modifier and exactly one key character at the end.
    static func from(string: String) -> KeyCombo? {
        guard !string.isEmpty else { return nil }

        var flags: NSEvent.ModifierFlags = []
        var remaining = string

        // Parse modifier symbols from the front using lookup table
        while let first = remaining.first, let modifier = modifierMap[first] {
            flags.insert(modifier)
            remaining.removeFirst()
        }

        // Must have at least one modifier and exactly one key character left
        guard !flags.isEmpty, remaining.count == 1 else { return nil }

        // Try the raw character first (for non-alpha keys like , . ⌫), then uppercased
        let keyChar = Self.keyCodeMap[remaining] != nil ? remaining : remaining.uppercased()
        guard let code = Self.keyCodeMap[keyChar] else { return nil }

        return KeyCombo(keyCode: code, modifiers: flags)
    }

    /// Returns the human-readable display string (e.g. "⌥⇧W").
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }

        for (key, code) in Self.keyCodeMap where code == keyCode {
            result += key
            break
        }
        return result
    }

    static let modifierMap: [Character: NSEvent.ModifierFlags] = [
        "⌘": .command,
        "⌥": .option,
        "⇧": .shift,
        "⌃": .control
    ]

    static let keyCodeMap: [String: UInt16] = [
        "A": UInt16(kVK_ANSI_A),
        "B": UInt16(kVK_ANSI_B),
        "C": UInt16(kVK_ANSI_C),
        "D": UInt16(kVK_ANSI_D),
        "E": UInt16(kVK_ANSI_E),
        "F": UInt16(kVK_ANSI_F),
        "G": UInt16(kVK_ANSI_G),
        "H": UInt16(kVK_ANSI_H),
        "I": UInt16(kVK_ANSI_I),
        "J": UInt16(kVK_ANSI_J),
        "K": UInt16(kVK_ANSI_K),
        "L": UInt16(kVK_ANSI_L),
        "M": UInt16(kVK_ANSI_M),
        "N": UInt16(kVK_ANSI_N),
        "O": UInt16(kVK_ANSI_O),
        "P": UInt16(kVK_ANSI_P),
        "Q": UInt16(kVK_ANSI_Q),
        "R": UInt16(kVK_ANSI_R),
        "S": UInt16(kVK_ANSI_S),
        "T": UInt16(kVK_ANSI_T),
        "U": UInt16(kVK_ANSI_U),
        "V": UInt16(kVK_ANSI_V),
        "W": UInt16(kVK_ANSI_W),
        "X": UInt16(kVK_ANSI_X),
        "Y": UInt16(kVK_ANSI_Y),
        "Z": UInt16(kVK_ANSI_Z),
        ",": UInt16(kVK_ANSI_Comma),
        ".": UInt16(kVK_ANSI_Period),
        "/": UInt16(kVK_ANSI_Slash),
        "⌫": UInt16(kVK_Delete)
    ]
}

// MARK: - HotkeyManager

/// Manages a global keyboard shortcut using Carbon `RegisterEventHotKey`.
/// Unlike `NSEvent.addGlobalMonitorForEvents`, the Carbon API does NOT
/// require accessibility permissions, making it reliable for unsigned debug builds.
@MainActor
final class HotkeyManager {

    // MARK: - Properties

    private(set) var isRegistered = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var currentCombo: KeyCombo?
    private var action: (() -> Void)?
    private var enabled = true

    /// Shared instance map for routing Carbon callbacks back to the right manager.
    private static var activeManager: HotkeyManager?

    // MARK: - Public API

    /// Registers a global hotkey with the given key combo string (e.g. "⌥⇧W").
    /// The `handler` closure is called on the main thread when the hotkey is pressed.
    func register(keyCombo: String, handler: @escaping () -> Void) {
        guard let combo = KeyCombo.from(string: keyCombo) else {
            logger.warning("Invalid key combo string: \(keyCombo)")
            return
        }

        unregister()

        currentCombo = combo
        action = handler
        enabled = true
        Self.activeManager = self

        installHotKey(for: combo)
        isRegistered = true
        logger.info("Registered global hotkey: \(combo.displayString)")
    }

    /// Removes the current global hotkey registration.
    func unregister() {
        removeHotKey()
        isRegistered = false
    }

    /// Enables or disables the hotkey without losing the configured combo.
    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled {
            guard let combo = currentCombo else { return }
            Self.activeManager = self
            installHotKey(for: combo)
            isRegistered = true
            logger.info("Re-enabled global hotkey: \(combo.displayString)")
        } else {
            removeHotKey()
            isRegistered = false
            logger.info("Disabled global hotkey")
        }
    }

    // MARK: - Carbon Hot Key Registration

    private func installHotKey(for combo: KeyCombo) {
        removeHotKey()

        // Install Carbon event handler for kEventHotKeyPressed
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, _ in
            DispatchQueue.main.async {
                HotkeyManager.activeManager?.action?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        // Register the hotkey with a unique signature "OMWT"
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x4F4D_5754),  // "OMWT"
            id: 1
        )
        let carbonMods = Self.carbonModifiers(from: combo.modifiers)

        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            carbonMods,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            logger.error("RegisterEventHotKey failed with status: \(status)")
        }
    }

    private func removeHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
