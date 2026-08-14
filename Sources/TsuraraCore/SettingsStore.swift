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
    public static let autoCloseSecondsRange: ClosedRange<Int> = 5...60
    public static let defaultAutoCloseSeconds = 15

    private enum Key: String {
        case launchAtLogin = "com.ysj.Tsurara.launchAtLogin"
        case alwaysHiddenSectionEnabled = "com.ysj.Tsurara.alwaysHiddenSectionEnabled"
        // 永続化キーは既存ユーザーの設定を引き継ぐため変更しない。
        case autoCloseEnabled = "com.ysj.Tsurara.autoRehideEnabled"
        case autoCloseSeconds = "com.ysj.Tsurara.autoRehideSeconds"
        case toggleHotkey = "com.ysj.Tsurara.toggleHotkey"
        case hasRequestedScreenCaptureAccess =
            "com.ysj.Tsurara.hasRequestedScreenCaptureAccess"
        case hasRequestedAccessibilityAccess =
            "com.ysj.Tsurara.hasRequestedAccessibilityAccess"
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

    public var autoCloseEnabled: Bool {
        get { defaults.object(forKey: Key.autoCloseEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoCloseEnabled.rawValue) }
    }

    /// 秒数は読み書き双方向で 5〜60 に制限する。外部から範囲外の値が
    /// 書き込まれても（defaults write 等）、呼び出し側には常に範囲内の値を返す。
    public var autoCloseSeconds: Int {
        get {
            let stored = defaults.object(forKey: Key.autoCloseSeconds.rawValue) as? Int
            return Self.clampSeconds(stored ?? Self.defaultAutoCloseSeconds)
        }
        set {
            defaults.set(Self.clampSeconds(newValue), forKey: Key.autoCloseSeconds.rawValue)
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

    /// CoreGraphics が未決定と拒否を区別できないため、システムの権限
    /// リクエストを提示した事実だけを保持する。拒否済みの断定には使わない。
    public var hasRequestedScreenCaptureAccess: Bool {
        get {
            defaults.object(forKey: Key.hasRequestedScreenCaptureAccess.rawValue)
                as? Bool ?? false
        }
        set {
            if newValue {
                defaults.set(true, forKey: Key.hasRequestedScreenCaptureAccess.rawValue)
            } else {
                defaults.removeObject(forKey: Key.hasRequestedScreenCaptureAccess.rawValue)
            }
        }
    }

    /// Accessibility のシステムプロンプトを提示した事実だけを保持する。
    /// AX API の false は回答待ちも含むため、拒否済みの断定には使わない。
    public var hasRequestedAccessibilityAccess: Bool {
        get {
            defaults.object(forKey: Key.hasRequestedAccessibilityAccess.rawValue)
                as? Bool ?? false
        }
        set {
            if newValue {
                defaults.set(true, forKey: Key.hasRequestedAccessibilityAccess.rawValue)
            } else {
                defaults.removeObject(forKey: Key.hasRequestedAccessibilityAccess.rawValue)
            }
        }
    }

    private static func clampSeconds(_ value: Int) -> Int {
        min(max(value, autoCloseSecondsRange.lowerBound), autoCloseSecondsRange.upperBound)
    }
}
