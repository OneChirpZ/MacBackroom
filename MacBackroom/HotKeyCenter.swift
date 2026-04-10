import AppKit
import Carbon.HIToolbox

final class HotKeyCenter {
    struct Shortcut: Codable, Equatable {
        let keyCode: UInt32
        let modifierFlagsRawValue: UInt
        let keyDisplay: String

        var modifiers: NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
        }

        var displayString: String {
            var value = ""

            if modifiers.contains(.control) {
                value += "⌃"
            }
            if modifiers.contains(.option) {
                value += "⌥"
            }
            if modifiers.contains(.shift) {
                value += "⇧"
            }
            if modifiers.contains(.command) {
                value += "⌘"
            }

            return value + keyDisplay
        }

        init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, keyDisplay: String) {
            self.keyCode = keyCode
            self.modifierFlagsRawValue = Self.recordableModifiers(from: modifiers).rawValue
            self.keyDisplay = Self.normalizedDisplayString(for: keyDisplay)
        }

        init?(event: NSEvent) {
            let modifiers = Self.recordableModifiers(from: event.modifierFlags)
            let keyCode = UInt32(event.keyCode)

            guard !modifiers.isEmpty, !Self.isModifierOnlyKeyCode(keyCode) else {
                return nil
            }

            self.init(
                keyCode: keyCode,
                modifiers: modifiers,
                keyDisplay: Self.displayKey(for: keyCode, eventCharacters: event.charactersIgnoringModifiers)
            )
        }

        func hasSameTrigger(as other: Shortcut) -> Bool {
            keyCode == other.keyCode && modifiers == other.modifiers
        }

        static func recordableModifiers(from modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
            modifiers.intersection([.command, .control, .option, .shift])
        }

        static func isModifierOnlyKeyCode(_ keyCode: UInt32) -> Bool {
            modifierOnlyKeyCodes.contains(keyCode)
        }

        static let switchLeft = Shortcut(
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: [.command, .control, .option],
            keyDisplay: "←"
        )

        static let switchRight = Shortcut(
            keyCode: UInt32(kVK_RightArrow),
            modifiers: [.command, .control, .option],
            keyDisplay: "→"
        )

        static let pasteTicketDate = Shortcut(
            keyCode: UInt32(kVK_ANSI_LeftBracket),
            modifiers: [.command, .control, .option],
            keyDisplay: "["
        )

        static let pasteCompactDate = Shortcut(
            keyCode: UInt32(kVK_ANSI_RightBracket),
            modifiers: [.command, .control, .option],
            keyDisplay: "]"
        )

        private static let modifierOnlyKeyCodes: Set<UInt32> = [
            UInt32(kVK_Command),
            UInt32(kVK_RightCommand),
            UInt32(kVK_Control),
            UInt32(kVK_RightControl),
            UInt32(kVK_Option),
            UInt32(kVK_RightOption),
            UInt32(kVK_Shift),
            UInt32(kVK_RightShift),
            UInt32(kVK_CapsLock),
            UInt32(kVK_Function)
        ]

        private static let specialKeyDisplays: [UInt32: String] = [
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_Escape): "⎋",
            UInt32(kVK_Home): "Home",
            UInt32(kVK_End): "End",
            UInt32(kVK_PageUp): "PgUp",
            UInt32(kVK_PageDown): "PgDn",
            UInt32(kVK_Help): "Help",
            UInt32(kVK_F1): "F1",
            UInt32(kVK_F2): "F2",
            UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4",
            UInt32(kVK_F5): "F5",
            UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7",
            UInt32(kVK_F8): "F8",
            UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10",
            UInt32(kVK_F11): "F11",
            UInt32(kVK_F12): "F12",
            UInt32(kVK_F13): "F13",
            UInt32(kVK_F14): "F14",
            UInt32(kVK_F15): "F15",
            UInt32(kVK_F16): "F16",
            UInt32(kVK_F17): "F17",
            UInt32(kVK_F18): "F18",
            UInt32(kVK_F19): "F19",
            UInt32(kVK_F20): "F20"
        ]

        private static let ansiKeyDisplays: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A",
            UInt32(kVK_ANSI_B): "B",
            UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_E): "E",
            UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G",
            UInt32(kVK_ANSI_H): "H",
            UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J",
            UInt32(kVK_ANSI_K): "K",
            UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M",
            UInt32(kVK_ANSI_N): "N",
            UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q",
            UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S",
            UInt32(kVK_ANSI_T): "T",
            UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V",
            UInt32(kVK_ANSI_W): "W",
            UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y",
            UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0",
            UInt32(kVK_ANSI_1): "1",
            UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4",
            UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6",
            UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_Minus): "-",
            UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[",
            UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Semicolon): ";",
            UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",",
            UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/",
            UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Grave): "`"
        ]

        private static func displayKey(for keyCode: UInt32, eventCharacters: String?) -> String {
            if let specialKeyDisplay = specialKeyDisplays[keyCode] {
                return specialKeyDisplay
            }

            if let eventCharacters,
               let normalizedEventCharacters = normalizedEventCharacters(eventCharacters) {
                return normalizedEventCharacters
            }

            if let ansiKeyDisplay = ansiKeyDisplays[keyCode] {
                return ansiKeyDisplay
            }

            return "Key \(keyCode)"
        }

        private static func normalizedEventCharacters(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            return normalizedDisplayString(for: trimmed)
        }

        private static func normalizedDisplayString(for value: String) -> String {
            if value.count == 1, let scalar = value.unicodeScalars.first, CharacterSet.letters.contains(scalar) {
                return value.uppercased()
            }

            return value
        }
    }

    struct Registration {
        let shortcut: Shortcut
        let handler: () -> Void
    }

    enum Error: LocalizedError {
        case installHandler(OSStatus)
        case registerHotKey(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .installHandler(status):
                return "InstallEventHandler failed with status \(status)."
            case let .registerHotKey(status):
                return "RegisterEventHotKey failed with status \(status)."
            }
        }
    }

    private static let signature = fourCharCode(from: "FSSW")

    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]

    init() throws {
        try installHandler()
    }

    deinit {
        unregisterAll()
    }

    func register(shortcut: Shortcut, handler: @escaping () -> Void) throws {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextID)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers(from: shortcut.modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            throw Error.registerHotKey(status)
        }

        hotKeyRefs[nextID] = hotKeyRef
        handlers[nextID] = handler
        nextID += 1
    }

    func replaceAll(with registrations: [Registration]) throws {
        unregisterAll()

        do {
            for registration in registrations {
                try register(shortcut: registration.shortcut, handler: registration.handler)
            }
        } catch {
            unregisterAll()
            throw error
        }
    }

    func unregisterAll() {
        for reference in hotKeyRefs.values {
            UnregisterEventHotKey(reference)
        }

        hotKeyRefs.removeAll()
        handlers.removeAll()
        nextID = 1
    }

    private func installHandler() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.eventHandlerProc,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            throw Error.installHandler(status)
        }
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return status
        }

        handlers[hotKeyID.id]?()
        return noErr
    }

    private static let eventHandlerProc: EventHandlerUPP = { _, event, userData in
        guard
            let event,
            let userData
        else {
            return OSStatus(eventNotHandledErr)
        }

        let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
        return center.handleHotKeyEvent(event)
    }
}

private func carbonModifiers(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
    var result: UInt32 = 0

    if modifiers.contains(.command) {
        result |= UInt32(cmdKey)
    }
    if modifiers.contains(.control) {
        result |= UInt32(controlKey)
    }
    if modifiers.contains(.option) {
        result |= UInt32(optionKey)
    }
    if modifiers.contains(.shift) {
        result |= UInt32(shiftKey)
    }

    return result
}

private func fourCharCode(from value: String) -> OSType {
    value.utf16.reduce(0) { partialResult, scalar in
        (partialResult << 8) + OSType(scalar)
    }
}
