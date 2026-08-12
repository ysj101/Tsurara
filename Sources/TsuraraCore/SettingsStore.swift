import Foundation

public struct HotkeyConfiguration: Codable, Equatable, Sendable {
    public let keyCode: Int
    public let modifierFlags: Int

    public init(keyCode: Int, modifierFlags: Int) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
}

// 可変の格納プロパティを持たず、UserDefaults はスレッドセーフが保証されているため
// @unchecked で Sendable を明示する（SDK の UserDefaults は Sendable 未宣言）。
public final class SettingsStore: @unchecked Sendable {
    public static let autoRehideSecondsRange: ClosedRange<Int> = 5...60
    public static let defaultAutoRehideSeconds = 15

    private enum Key: String {
        case launchAtLogin = "com.ysj.Tsurara.launchAtLogin"
        case alwaysHiddenSectionEnabled = "com.ysj.Tsurara.alwaysHiddenSectionEnabled"
        case autoRehideEnabled = "com.ysj.Tsurara.autoRehideEnabled"
        case autoRehideSeconds = "com.ysj.Tsurara.autoRehideSeconds"
        case toggleHotkey = "com.ysj.Tsurara.toggleHotkey"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var launchAtLogin: Bool {
        get { defaults.object(forKey: Key.launchAtLogin.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.launchAtLogin.rawValue) }
    }

    public var alwaysHiddenSectionEnabled: Bool {
        get { defaults.object(forKey: Key.alwaysHiddenSectionEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.alwaysHiddenSectionEnabled.rawValue) }
    }

    public var autoRehideEnabled: Bool {
        get { defaults.object(forKey: Key.autoRehideEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoRehideEnabled.rawValue) }
    }

    /// 秒数は読み書き双方向で 5〜60 に制限する。外部から範囲外の値が
    /// 書き込まれても（defaults write 等）、呼び出し側には常に範囲内の値を返す。
    public var autoRehideSeconds: Int {
        get {
            let stored = defaults.object(forKey: Key.autoRehideSeconds.rawValue) as? Int
            return Self.clampSeconds(stored ?? Self.defaultAutoRehideSeconds)
        }
        set {
            defaults.set(Self.clampSeconds(newValue), forKey: Key.autoRehideSeconds.rawValue)
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
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                // エンコード不能時に古い割り当てを残すと「新しい割り当てが表示上は
                // 成功したのに旧ホットキーが発火し続ける」状態になるため、消去に倒す。
                defaults.removeObject(forKey: Key.toggleHotkey.rawValue)
                return
            }
            defaults.set(data, forKey: Key.toggleHotkey.rawValue)
        }
    }

    private static func clampSeconds(_ value: Int) -> Int {
        min(max(value, autoRehideSecondsRange.lowerBound), autoRehideSecondsRange.upperBound)
    }
}
