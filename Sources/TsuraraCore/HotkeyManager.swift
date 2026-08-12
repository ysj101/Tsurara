import Foundation

@MainActor
public protocol HotkeyRegistering {
    func register(
        _ configuration: HotkeyConfiguration,
        onPress: @escaping @MainActor () -> Void
    ) -> Bool
    func unregister()
}

@MainActor
public final class HotkeyManager {
    private let settings: SettingsStore
    private let registrar: any HotkeyRegistering
    private let onToggle: @MainActor () -> Void

    public init(
        settings: SettingsStore,
        registrar: any HotkeyRegistering,
        onToggle: @escaping @MainActor () -> Void
    ) {
        self.settings = settings
        self.registrar = registrar
        self.onToggle = onToggle
    }

    public func restoreFromSettings() {
        guard let configuration = settings.toggleHotkey else { return }
        _ = registrar.register(configuration, onPress: onToggle)
    }

    @discardableResult
    public func assign(_ configuration: HotkeyConfiguration?) -> Bool {
        guard let configuration else {
            registrar.unregister()
            settings.toggleHotkey = nil
            return true
        }

        guard registrar.register(configuration, onPress: onToggle) else {
            return false
        }

        settings.toggleHotkey = configuration
        return true
    }
}
