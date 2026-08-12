import Foundation

public struct HotkeyConfiguration: Codable, Equatable, Sendable {
    public let keyCode: Int
    public let modifierFlags: Int

    public init(keyCode: Int, modifierFlags: Int) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
}

public final class SettingsStore {
    private enum Key: String {
        case launchAtLogin
        case alwaysHiddenSectionEnabled
        case autoRehideEnabled
        case autoRehideSeconds
        case toggleHotkey
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin.rawValue) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin.rawValue) }
    }

    public var alwaysHiddenSectionEnabled: Bool {
        get { defaults.bool(forKey: Key.alwaysHiddenSectionEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.alwaysHiddenSectionEnabled.rawValue) }
    }

    public var autoRehideEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.autoRehideEnabled.rawValue) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.autoRehideEnabled.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.autoRehideEnabled.rawValue) }
    }

    public var autoRehideSeconds: Int {
        get {
            guard defaults.object(forKey: Key.autoRehideSeconds.rawValue) != nil else {
                return 15
            }
            return defaults.integer(forKey: Key.autoRehideSeconds.rawValue)
        }
        set {
            defaults.set(
                min(max(newValue, 5), 60),
                forKey: Key.autoRehideSeconds.rawValue
            )
        }
    }

    public var toggleHotkey: HotkeyConfiguration? {
        get {
            guard let data = defaults.data(forKey: Key.toggleHotkey.rawValue) else {
                return nil
            }
            return try? JSONDecoder().decode(HotkeyConfiguration.self, from: data)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.toggleHotkey.rawValue)
                return
            }

            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.toggleHotkey.rawValue)
            }
        }
    }
}
