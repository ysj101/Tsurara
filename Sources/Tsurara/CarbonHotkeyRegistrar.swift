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
    private var registeredConfiguration: HotkeyConfiguration?
    private var onPress: (@MainActor () -> Void)?

    init() {
        installEventHandlerIfNeeded()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
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
            NSLog("Tsurara: InstallEventHandler failed (OSStatus %d)", status)
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
        // 起動時にハンドラ設置へ失敗していても、次の登録時に再試行する。
        installEventHandlerIfNeeded()
        guard eventHandler != nil else {
            NSLog("Tsurara: ホットキー登録不可（イベントハンドラ未設置）")
            return false
        }
        guard let keyCode = HotkeyModifiers.validatedKeyCode(configuration.keyCode) else {
            // 破損した保存値（負数など）で UInt32 変換がクラッシュしないよう検証する。
            NSLog("Tsurara: 不正な keyCode %ld を無視", configuration.keyCode)
            return false
        }

        // 同一キーの再登録は eventHotKeyExistsErr になるため、先に既存登録を解除する。
        // 失敗時は旧登録を復元して「失敗しても現状維持」を守る。
        let previous = registeredConfiguration
        if let registeredHotKey {
            UnregisterEventHotKey(registeredHotKey)
            self.registeredHotKey = nil
        }

        var newHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            HotkeyModifiers.carbonModifiers(fromNSEventFlags: configuration.modifierFlags),
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKey
        )
        guard status == noErr, let newHotKey else {
            NSLog("Tsurara: RegisterEventHotKey failed (OSStatus %d)", status)
            if let previous, let previousOnPress = self.onPress {
                _ = register(previous, onPress: previousOnPress)
            }
            return false
        }

        registeredHotKey = newHotKey
        registeredConfiguration = configuration
        self.onPress = onPress
        return true
    }

    func unregister() {
        if let registeredHotKey {
            UnregisterEventHotKey(registeredHotKey)
        }
        registeredHotKey = nil
        registeredConfiguration = nil
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
}
