import AppKit
import ApplicationServices
import Carbon
@preconcurrency import CoreGraphics
import Foundation
import IOKit
import IOKit.hidsystem
import KotobaLibreCore

// This file bridges Swift code to the older macOS APIs used for global keyboard shortcuts.
// Carbon is the preferred backend, with Event Tap support added when permissions allow it.
final class GlobalShortcutRegistrar {
    private enum RegistrationBackend {
        case carbonOnly
        case carbonWithEventTap
        case eventTapOnly

        // The UI shows this label in shortcut diagnostics.
        var displayName: String {
            switch self {
            case .carbonOnly:
                return "Carbon"
            case .carbonWithEventTap:
                return "Carbon + Event Tap"
            case .eventTapOnly:
                return "Event Tap"
            }
        }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var activeDescriptor: ShortcutDescriptor?
    private var onShortcutPressed: (() -> Void)?
    private var registrationBackend: RegistrationBackend?
    private var lastTriggerTime: CFAbsoluteTime = 0
    private var lastCarbonStatus: OSStatus?

    // RuntimeStatus lets the settings UI explain why a shortcut did or did not register.
    struct RuntimeStatus {
        let activeShortcut: String?
        let backend: String
        let carbonRegistered: Bool
        let eventTapInstalled: Bool
        let accessibilityGranted: Bool
        let inputMonitoringGranted: Bool
        let lastCarbonStatus: OSStatus?
    }

    static func isShortcutSupportedBySystemPolicy(_ shortcut: String) -> Bool {
        // macOS rejects some modifier-only combinations as global shortcuts.
        let modifierTokens = KotobaLibreCore.normalizeShortcutValue(shortcut)
            .split(separator: "+")
            .map(String.init)
            .filter { ["CmdOrCtrl", "Ctrl", "Alt", "Shift"].contains($0) }

        guard !modifierTokens.isEmpty else {
            return false
        }

        return !modifierTokens.allSatisfy { token in
            token == "Alt" || token == "Shift"
        }
    }

    func register(
        shortcut: String,
        promptForPermission: Bool = true,
        onShortcutPressed: @escaping () -> Void
    ) throws {
        guard Self.isShortcutSupportedBySystemPolicy(shortcut) else {
            throw ShortcutRegistrationError.unsupportedBySystemPolicy(shortcut)
        }

        let descriptor = try ShortcutDescriptor(shortcut: shortcut)
        unregisterCurrentShortcut()

        self.activeDescriptor = descriptor
        self.onShortcutPressed = onShortcutPressed

        do {
            // Prefer Carbon because it works in the background without extra permissions on supported shortcuts.
            try installCarbonHotKey(descriptor: descriptor)
            registrationBackend = .carbonOnly
            // If permissions already exist, the event tap is added too to catch cases Carbon can miss.
            installSupplementalEventTapIfAvailable(descriptor: descriptor)
            return
        } catch {
            // If Carbon fails, fall back to an event tap and surface permission requirements if needed.
            try installEventTapFallback(descriptor: descriptor, promptForPermission: promptForPermission)
            registrationBackend = .eventTapOnly
        }
    }

    func unregisterCurrentShortcut() {
        // Both registration backends are cleaned up because the active path can change across saves.
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            self.eventTapSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        activeDescriptor = nil
        onShortcutPressed = nil
        registrationBackend = nil
        lastCarbonStatus = nil
    }

    func runtimeStatus() -> RuntimeStatus {
        RuntimeStatus(
            activeShortcut: activeDescriptor?.normalizedShortcut,
            backend: registrationBackend?.displayName ?? "Unavailable",
            carbonRegistered: hotKeyRef != nil,
            eventTapInstalled: eventTap != nil,
            accessibilityGranted: Self.currentAccessibilityTrust(),
            inputMonitoringGranted: Self.currentInputMonitoringTrust(),
            lastCarbonStatus: lastCarbonStatus
        )
    }

    static func shortcutString(from event: NSEvent) -> String? {
        // This converts a live key press into the same token format used in settings storage.
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
        return KotobaLibreCore.normalizeShortcutValue(parts.joined(separator: "+"))
    }

    private func installCarbonHotKey(descriptor: ShortcutDescriptor) throws {
        try installCarbonHandlerIfNeeded()

        // Carbon needs a stable integer id so the callback can map back to this registration.
        let hotKeyID = EventHotKeyID(signature: OSType(0x544C4853), id: descriptor.id)
        let status = RegisterEventHotKey(
            UInt32(descriptor.keyCode),
            descriptor.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        lastCarbonStatus = status

        guard status == noErr else {
            throw ShortcutRegistrationError.registrationFailed(descriptor.normalizedShortcut)
        }
    }

    private func installCarbonHandlerIfNeeded() throws {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Carbon callbacks are C functions. Unmanaged is the bridge that carries Swift self through userData.
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else {
                return noErr
            }

            let registrar = Unmanaged<GlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
            registrar.triggerShortcutIfNeeded()
            return noErr
        }

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        lastCarbonStatus = status

        guard status == noErr else {
            throw ShortcutRegistrationError.registrationFailed(activeShortcut)
        }
    }

    private func installEventTapFallback(
        descriptor: ShortcutDescriptor,
        promptForPermission: Bool
    ) throws {
        try ensureEventTapPermissions(promptForPermission: promptForPermission, shortcut: descriptor.normalizedShortcut)
        try installEventTap(descriptor: descriptor)
    }

    private func installSupplementalEventTapIfAvailable(descriptor: ShortcutDescriptor) {
        guard Self.currentAccessibilityTrust(), Self.currentInputMonitoringTrust() else {
            return
        }

        do {
            try ensureEventTapPermissions(promptForPermission: false, shortcut: descriptor.normalizedShortcut)
            try installEventTap(descriptor: descriptor)
            registrationBackend = .carbonWithEventTap
        } catch {
            // Carbon registration is already active, so we keep it and surface no supplemental error here.
        }
    }

    private func ensureEventTapPermissions(promptForPermission: Bool, shortcut: String) throws {
        var accessibilityTrusted = Self.currentAccessibilityTrust()
        if !accessibilityTrusted && promptForPermission {
            accessibilityTrusted = Self.requestAccessibilityTrustPrompt()
        }

        guard accessibilityTrusted else {
            throw ShortcutRegistrationError.accessibilityPermissionRequired(shortcut)
        }
    }

    private func installEventTap(descriptor: ShortcutDescriptor) throws {
        // Event tap creation doubles as a practical check for background key-listening permission.
        let inputMonitoringTrustedBeforeTap = Self.currentInputMonitoringTrust()
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userData in
            guard let userData else {
                return Unmanaged.passUnretained(event)
            }

            let registrar = Unmanaged<GlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
            return registrar.handleEventTap(type: type, event: event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            if !Self.currentInputMonitoringTrust() {
                throw ShortcutRegistrationError.inputMonitoringPermissionRequired(descriptor.normalizedShortcut)
            }
            throw ShortcutRegistrationError.registrationFailed(descriptor.normalizedShortcut)
        }

        if !inputMonitoringTrustedBeforeTap && !Self.currentInputMonitoringTrust() {
            CFMachPortInvalidate(eventTap)
            throw ShortcutRegistrationError.inputMonitoringPermissionRequired(descriptor.normalizedShortcut)
        }

        guard let eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            throw ShortcutRegistrationError.registrationFailed(descriptor.normalizedShortcut)
        }

        self.eventTap = eventTap
        self.eventTapSource = eventTapSource

        CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private static func currentAccessibilityTrust() -> Bool {
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
    }

    private static func requestAccessibilityTrustPrompt() -> Bool {
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private static func currentInputMonitoringTrust() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS can disable taps under load, so we re-enable ours when possible.
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        case .keyDown:
            if matchesRegisteredShortcut(event: event) {
                triggerShortcutIfNeeded()
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func matchesRegisteredShortcut(event: CGEvent) -> Bool {
        guard let activeDescriptor else {
            return false
        }

        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return false
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == activeDescriptor.keyCode else {
            return false
        }

        let flags = event.flags.intersection(Self.relevantEventFlags)
        return flags == activeDescriptor.requiredEventFlags
    }

    private var activeShortcut: String {
        activeDescriptor?.normalizedShortcut ?? "unknown"
    }

    private func triggerShortcutIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        // Debounce protects against double fires when Carbon and Event Tap both observe the same key press.
        guard now - lastTriggerTime > 0.2 else {
            return
        }

        lastTriggerTime = now
        onShortcutPressed?()
    }

    private static let relevantEventFlags: CGEventFlags = [
        .maskCommand,
        .maskControl,
        .maskAlternate,
        .maskShift
    ]

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

// ShortcutDescriptor is the normalized, low-level form used by Carbon and Event Tap registration.
private struct ShortcutDescriptor {
    let id: UInt32
    let normalizedShortcut: String
    let keyCode: Int
    let carbonModifiers: UInt32
    let requiredEventFlags: CGEventFlags

    init(shortcut: String) throws {
        let normalized = KotobaLibreCore.normalizeShortcutValue(shortcut)
        let tokens = normalized.split(separator: "+").map(String.init)
        guard !tokens.isEmpty else {
            throw ShortcutRegistrationError.invalidShortcut(shortcut)
        }

        var carbonModifiers: UInt32 = 0
        var requiredEventFlags: CGEventFlags = []
        var keyToken: String?

        for token in tokens {
            switch token {
            case "CmdOrCtrl":
                carbonModifiers |= UInt32(cmdKey)
                requiredEventFlags.insert(.maskCommand)
            case "Ctrl":
                carbonModifiers |= UInt32(controlKey)
                requiredEventFlags.insert(.maskControl)
            case "Alt":
                carbonModifiers |= UInt32(optionKey)
                requiredEventFlags.insert(.maskAlternate)
            case "Shift":
                carbonModifiers |= UInt32(shiftKey)
                requiredEventFlags.insert(.maskShift)
            default:
                keyToken = token
            }
        }

        guard carbonModifiers != 0, let keyToken, let keyCode = Self.keyCode(for: keyToken) else {
            throw ShortcutRegistrationError.invalidShortcut(shortcut)
        }

        self.id = UInt32(truncatingIfNeeded: normalized.hashValue)
        self.normalizedShortcut = normalized
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.requiredEventFlags = requiredEventFlags
    }

    private static func keyCode(for token: String) -> Int? {
        // The stored shortcut uses web-style key tokens, so we map them to macOS virtual key codes here.
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

// These errors are written for end users, so each case includes recovery guidance when possible.
enum ShortcutRegistrationError: LocalizedError {
    case invalidShortcut(String)
    case registrationFailed(String)
    case unsupportedBySystemPolicy(String)
    case accessibilityPermissionRequired(String)
    case inputMonitoringPermissionRequired(String)

    var errorDescription: String? {
        switch self {
        case let .invalidShortcut(value):
            return "Unsupported global shortcut: \(value)"
        case let .registrationFailed(value):
            return "Failed to register global shortcut: \(value)"
        case let .unsupportedBySystemPolicy(value):
            return "macOS does not allow '\(value)' as a global shortcut. Use a shortcut that includes Control or Command."
        case let .accessibilityPermissionRequired(value):
            return "Kotoba Libre needs Accessibility permission to use '\(value)' when Carbon registration is unavailable. Allow Kotoba Libre in System Settings > Privacy & Security > Accessibility, then relaunch the app if macOS asks for it."
        case let .inputMonitoringPermissionRequired(value):
            return "Kotoba Libre needs Input Monitoring permission to use '\(value)' while the app is in the background. Allow Kotoba Libre in System Settings > Privacy & Security > Input Monitoring, then relaunch the app if macOS asks for it."
        }
    }
}
