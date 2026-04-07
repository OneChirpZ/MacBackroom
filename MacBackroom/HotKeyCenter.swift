import AppKit
import Carbon.HIToolbox

final class HotKeyCenter {
    struct Shortcut {
        let keyCode: UInt32
        let modifiers: NSEvent.ModifierFlags
        let displayString: String

        static let switchLeft = Shortcut(
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: [.command, .control, .option],
            displayString: "⌃⌥⌘←"
        )

        static let switchRight = Shortcut(
            keyCode: UInt32(kVK_RightArrow),
            modifiers: [.command, .control, .option],
            displayString: "⌃⌥⌘→"
        )
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
        for reference in hotKeyRefs.values {
            UnregisterEventHotKey(reference)
        }
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
