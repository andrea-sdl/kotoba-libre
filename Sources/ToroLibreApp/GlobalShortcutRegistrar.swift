import AppKit
import Carbon
import Foundation
import ToroLibreCore

@MainActor
final class GlobalShortcutRegistrar {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onShortcutPressed: (() -> Void)?

    init() {
        installHandlerIfNeeded()
    }

    func register(shortcut: String, onShortcutPressed: @escaping () -> Void) throws {
        unregisterCurrentShortcut()
        self.onShortcutPressed = onShortcutPressed

        let descriptor = try ShortcutDescriptor(shortcut: shortcut)
        let hotKeyID = EventHotKeyID(signature: OSType(0x544C4853), id: descriptor.id)
        let status = RegisterEventHotKey(
            UInt32(descriptor.keyCode),
            descriptor.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            throw ShortcutRegistrationError.registrationFailed(shortcut)
        }
    }

    func unregisterCurrentShortcut() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    static func shortcutString(from event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !flags.isEmpty else {
            return nil
        }

        let key = keyToken(for: event)
        guard let key else {
            return nil
        }

        var parts: [String] = []
        if flags.contains(.command) {
            parts.append("CmdOrCtrl")
        }
        if flags.contains(.control) && !flags.contains(.command) {
            parts.append("Ctrl")
        }
        if flags.contains(.option) {
            parts.append("Alt")
        }
        if flags.contains(.shift) {
            parts.append("Shift")
        }
        parts.append(key)
        return ToroLibreCore.normalizeShortcutValue(parts.joined(separator: "+"))
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else {
                return noErr
            }

            let registrar = Unmanaged<GlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
            registrar.onShortcutPressed?()
            return noErr
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private static func keyToken(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 49: return "Space"
        case 36: return "Enter"
        case 48: return "Tab"
        case 53: return "Escape"
        case 51: return "Backspace"
        case 117: return "Delete"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "PageUp"
        case 121: return "PageDown"
        case 126: return "ArrowUp"
        case 125: return "ArrowDown"
        case 123: return "ArrowLeft"
        case 124: return "ArrowRight"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers?.uppercased(), let first = characters.first else {
            return nil
        }

        if first.isLetter {
            return "Key\(String(first))"
        }
        if first.isNumber {
            return "Digit\(String(first))"
        }

        switch first {
        case "-": return "Minus"
        case "=": return "Equal"
        case "[": return "BracketLeft"
        case "]": return "BracketRight"
        case "\\": return "Backslash"
        case ";": return "Semicolon"
        case "'": return "Quote"
        case ",": return "Comma"
        case ".": return "Period"
        case "/": return "Slash"
        case "`": return "Backquote"
        default: return nil
        }
    }
}

private struct ShortcutDescriptor {
    let id: UInt32
    let keyCode: Int
    let modifiers: UInt32

    init(shortcut: String) throws {
        let normalized = ToroLibreCore.normalizeShortcutValue(shortcut)
        let tokens = normalized.split(separator: "+").map(String.init)
        guard !tokens.isEmpty else {
            throw ShortcutRegistrationError.invalidShortcut(shortcut)
        }

        var carbonModifiers: UInt32 = 0
        var keyToken: String?

        for token in tokens {
            switch token {
            case "CmdOrCtrl":
                carbonModifiers |= UInt32(cmdKey)
            case "Ctrl":
                carbonModifiers |= UInt32(controlKey)
            case "Alt":
                carbonModifiers |= UInt32(optionKey)
            case "Shift":
                carbonModifiers |= UInt32(shiftKey)
            default:
                keyToken = token
            }
        }

        guard carbonModifiers != 0, let keyToken, let keyCode = Self.keyCode(for: keyToken) else {
            throw ShortcutRegistrationError.invalidShortcut(shortcut)
        }

        self.id = UInt32(truncatingIfNeeded: normalized.hashValue)
        self.keyCode = keyCode
        self.modifiers = carbonModifiers
    }

    private static func keyCode(for token: String) -> Int? {
        let mapping: [String: Int] = [
            "Space": 49,
            "Enter": 36,
            "Tab": 48,
            "Escape": 53,
            "Backspace": 51,
            "Delete": 117,
            "Home": 115,
            "End": 119,
            "PageUp": 116,
            "PageDown": 121,
            "ArrowUp": 126,
            "ArrowDown": 125,
            "ArrowLeft": 123,
            "ArrowRight": 124,
            "Minus": 27,
            "Equal": 24,
            "BracketLeft": 33,
            "BracketRight": 30,
            "Backslash": 42,
            "Semicolon": 41,
            "Quote": 39,
            "Comma": 43,
            "Period": 47,
            "Slash": 44,
            "Backquote": 50,
            "F1": 122,
            "F2": 120,
            "F3": 99,
            "F4": 118,
            "F5": 96,
            "F6": 97,
            "F7": 98,
            "F8": 100,
            "F9": 101,
            "F10": 109,
            "F11": 103,
            "F12": 111
        ]

        if let mapped = mapping[token] {
            return mapped
        }

        let alphaNumeric: [String: Int] = [
            "KeyA": 0, "KeyS": 1, "KeyD": 2, "KeyF": 3, "KeyH": 4, "KeyG": 5, "KeyZ": 6, "KeyX": 7,
            "KeyC": 8, "KeyV": 9, "KeyB": 11, "KeyQ": 12, "KeyW": 13, "KeyE": 14, "KeyR": 15,
            "KeyY": 16, "KeyT": 17, "Digit1": 18, "Digit2": 19, "Digit3": 20, "Digit4": 21,
            "Digit6": 22, "Digit5": 23, "Equal": 24, "Digit9": 25, "Digit7": 26, "Minus": 27,
            "Digit8": 28, "Digit0": 29, "BracketRight": 30, "KeyO": 31, "KeyU": 32, "BracketLeft": 33,
            "KeyI": 34, "KeyP": 35, "KeyL": 37, "KeyJ": 38, "Quote": 39, "KeyK": 40, "Semicolon": 41,
            "Backslash": 42, "Comma": 43, "Slash": 44, "KeyN": 45, "KeyM": 46, "Period": 47,
            "Backquote": 50
        ]

        return alphaNumeric[token]
    }
}

enum ShortcutRegistrationError: LocalizedError {
    case invalidShortcut(String)
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidShortcut(value):
            return "Unsupported global shortcut: \(value)"
        case let .registrationFailed(value):
            return "Failed to register global shortcut: \(value)"
        }
    }
}
