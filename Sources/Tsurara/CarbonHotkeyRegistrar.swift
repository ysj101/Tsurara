import AppKit
import Carbon
import TsuraraCore

@MainActor
final class CarbonHotkeyRegistrar: HotkeyRegistering {
    private static let hotKeyID = EventHotKeyID(
        signature: OSType(0x5453_5552), // "TSUR"
        id: 1
    )

    private var eventHandler: EventHandlerRef?
    private var registeredHotKey: EventHotKeyRef?
    private var onPress: (@MainActor () -> Void)?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleEvent,
            1,
            &eventType,
            userData,
            &eventHandler
        )
        if status != noErr {
            eventHandler = nil
        }
    }

    isolated deinit {
        if let registeredHotKey {
            UnregisterEventHotKey(registeredHotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(
        _ configuration: HotkeyConfiguration,
        onPress: @escaping @MainActor () -> Void
    ) -> Bool {
        guard eventHandler != nil else { return false }

        var newHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(configuration.keyCode),
            Self.carbonModifiers(from: configuration.modifierFlags),
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKey
        )
        guard status == noErr, let newHotKey else { return false }

        if let registeredHotKey {
            UnregisterEventHotKey(registeredHotKey)
        }
        registeredHotKey = newHotKey
        self.onPress = onPress
        return true
    }

    func unregister() {
        if let registeredHotKey {
            UnregisterEventHotKey(registeredHotKey)
        }
        registeredHotKey = nil
        onPress = nil
    }

    private func hotKeyPressed() {
        onPress?()
    }

    private static let handleEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var pressedID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &pressedID
        )
        guard status == noErr,
              pressedID.signature == hotKeyID.signature,
              pressedID.id == hotKeyID.id
        else {
            return OSStatus(eventNotHandledErr)
        }

        let registrar = Unmanaged<CarbonHotkeyRegistrar>
            .fromOpaque(userData)
            .takeUnretainedValue()
        MainActor.assumeIsolated {
            registrar.hotKeyPressed()
        }
        return noErr
    }

    private static func carbonModifiers(from rawValue: Int) -> UInt32 {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(rawValue))
        var result: UInt32 = 0

        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.capsLock) { result |= UInt32(alphaLock) }
        if modifiers.contains(.function) { result |= UInt32(kEventKeyModifierFnMask) }
        if modifiers.contains(.numericPad) { result |= UInt32(kEventKeyModifierNumLockMask) }

        return result
    }
}
