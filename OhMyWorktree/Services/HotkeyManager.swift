import AppKit
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.ohmyworktree", category: "HotkeyManager")

// MARK: - KeyCombo

/// A single key entry mapping display character, SwiftUI character, and Carbon key code.
struct KeyMapping {
    let displayChar: String      // "W", ",", "⌫"
    let swiftUIChar: Character   // "w", ",", \u{8} (delete)
    let keyCode: UInt16          // kVK_ANSI_W
}

/// Represents a keyboard shortcut combination (modifier flags + key code).
struct KeyCombo: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    // MARK: - Single Source of Truth

    static let allKeys: [KeyMapping] = [
        KeyMapping(displayChar: "A", swiftUIChar: "a", keyCode: UInt16(kVK_ANSI_A)),
        KeyMapping(displayChar: "B", swiftUIChar: "b", keyCode: UInt16(kVK_ANSI_B)),
        KeyMapping(displayChar: "C", swiftUIChar: "c", keyCode: UInt16(kVK_ANSI_C)),
        KeyMapping(displayChar: "D", swiftUIChar: "d", keyCode: UInt16(kVK_ANSI_D)),
        KeyMapping(displayChar: "E", swiftUIChar: "e", keyCode: UInt16(kVK_ANSI_E)),
        KeyMapping(displayChar: "F", swiftUIChar: "f", keyCode: UInt16(kVK_ANSI_F)),
        KeyMapping(displayChar: "G", swiftUIChar: "g", keyCode: UInt16(kVK_ANSI_G)),
        KeyMapping(displayChar: "H", swiftUIChar: "h", keyCode: UInt16(kVK_ANSI_H)),
        KeyMapping(displayChar: "I", swiftUIChar: "i", keyCode: UInt16(kVK_ANSI_I)),
        KeyMapping(displayChar: "J", swiftUIChar: "j", keyCode: UInt16(kVK_ANSI_J)),
        KeyMapping(displayChar: "K", swiftUIChar: "k", keyCode: UInt16(kVK_ANSI_K)),
        KeyMapping(displayChar: "L", swiftUIChar: "l", keyCode: UInt16(kVK_ANSI_L)),
        KeyMapping(displayChar: "M", swiftUIChar: "m", keyCode: UInt16(kVK_ANSI_M)),
        KeyMapping(displayChar: "N", swiftUIChar: "n", keyCode: UInt16(kVK_ANSI_N)),
        KeyMapping(displayChar: "O", swiftUIChar: "o", keyCode: UInt16(kVK_ANSI_O)),
        KeyMapping(displayChar: "P", swiftUIChar: "p", keyCode: UInt16(kVK_ANSI_P)),
        KeyMapping(displayChar: "Q", swiftUIChar: "q", keyCode: UInt16(kVK_ANSI_Q)),
        KeyMapping(displayChar: "R", swiftUIChar: "r", keyCode: UInt16(kVK_ANSI_R)),
        KeyMapping(displayChar: "S", swiftUIChar: "s", keyCode: UInt16(kVK_ANSI_S)),
        KeyMapping(displayChar: "T", swiftUIChar: "t", keyCode: UInt16(kVK_ANSI_T)),
        KeyMapping(displayChar: "U", swiftUIChar: "u", keyCode: UInt16(kVK_ANSI_U)),
        KeyMapping(displayChar: "V", swiftUIChar: "v", keyCode: UInt16(kVK_ANSI_V)),
        KeyMapping(displayChar: "W", swiftUIChar: "w", keyCode: UInt16(kVK_ANSI_W)),
        KeyMapping(displayChar: "X", swiftUIChar: "x", keyCode: UInt16(kVK_ANSI_X)),
        KeyMapping(displayChar: "Y", swiftUIChar: "y", keyCode: UInt16(kVK_ANSI_Y)),
        KeyMapping(displayChar: "Z", swiftUIChar: "z", keyCode: UInt16(kVK_ANSI_Z)),
        KeyMapping(displayChar: ",", swiftUIChar: ",", keyCode: UInt16(kVK_ANSI_Comma)),
        KeyMapping(displayChar: ".", swiftUIChar: ".", keyCode: UInt16(kVK_ANSI_Period)),
        KeyMapping(displayChar: "/", swiftUIChar: "/", keyCode: UInt16(kVK_ANSI_Slash)),
        KeyMapping(displayChar: "⌫", swiftUIChar: Character(UnicodeScalar(8)), keyCode: UInt16(kVK_Delete))
    ]

    /// Display string → key code (for parsing shortcut strings like "⌥⇧W").
    static let keyCodeMap: [String: UInt16] = Dictionary(
        uniqueKeysWithValues: allKeys.map { ($0.displayChar, $0.keyCode) }
    )

    /// Key code → SwiftUI character (for converting to `KeyEquivalent`).
    static let keyCodeToSwiftUICharacter: [UInt16: Character] = Dictionary(
        uniqueKeysWithValues: allKeys.map { ($0.keyCode, $0.swiftUIChar) }
    )

    /// Key code → display string (for `displayString` reverse lookup).
    private static let keyCodeToDisplayChar: [UInt16: String] = Dictionary(
        uniqueKeysWithValues: allKeys.map { ($0.keyCode, $0.displayChar) }
    )

    // MARK: - Parsing

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

        // Must have exactly one key character left (modifiers optional for special keys like ⌫)
        guard remaining.count == 1 else { return nil }

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

        if let key = Self.keyCodeToDisplayChar[keyCode] {
            result += key
        }
        return result
    }

    static let modifierMap: [Character: NSEvent.ModifierFlags] = [
        "⌘": .command,
        "⌥": .option,
        "⇧": .shift,
        "⌃": .control
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
