import Observation

public final class SettingsViewModel: Observable {
    private let settings: SettingsStore
    private let registrar = ObservationRegistrar()
    private var storedLaunchAtLogin: Bool
    private var storedAlwaysHiddenSectionEnabled: Bool
    private var storedAutoRehideEnabled: Bool
    private var storedAutoRehideSeconds: Int

    // NOTE: 値の保存のみ。SMAppService への実登録は #13 で接続する。
    public var launchAtLogin: Bool {
        get {
            registrar.access(self, keyPath: \.launchAtLogin)
            return storedLaunchAtLogin
        }
        set {
            registrar.withMutation(of: self, keyPath: \.launchAtLogin) {
                storedLaunchAtLogin = newValue
                settings.launchAtLogin = newValue
            }
        }
    }

    public var alwaysHiddenSectionEnabled: Bool {
        get {
            registrar.access(self, keyPath: \.alwaysHiddenSectionEnabled)
            return storedAlwaysHiddenSectionEnabled
        }
        set {
            registrar.withMutation(of: self, keyPath: \.alwaysHiddenSectionEnabled) {
                storedAlwaysHiddenSectionEnabled = newValue
                settings.alwaysHiddenSectionEnabled = newValue
            }
        }
    }

    public var autoRehideEnabled: Bool {
        get {
            registrar.access(self, keyPath: \.autoRehideEnabled)
            return storedAutoRehideEnabled
        }
        set {
            registrar.withMutation(of: self, keyPath: \.autoRehideEnabled) {
                storedAutoRehideEnabled = newValue
                settings.autoRehideEnabled = newValue
            }
        }
    }

    public var autoRehideSeconds: Int {
        get {
            registrar.access(self, keyPath: \.autoRehideSeconds)
            return storedAutoRehideSeconds
        }
        set {
            registrar.withMutation(of: self, keyPath: \.autoRehideSeconds) {
                settings.autoRehideSeconds = newValue
                // SettingsStore remains the source of truth for range enforcement.
                storedAutoRehideSeconds = settings.autoRehideSeconds
            }
        }
    }

    public init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        storedLaunchAtLogin = settings.launchAtLogin
        storedAlwaysHiddenSectionEnabled = settings.alwaysHiddenSectionEnabled
        storedAutoRehideEnabled = settings.autoRehideEnabled
        storedAutoRehideSeconds = settings.autoRehideSeconds
    }

    /// ストアの現在値を再読込する。ウィンドウ再表示時や、SectionManager など
    /// ビュー外の経路で設定が書き換えられた後の同期に使う。
    public func refresh() {
        registrar.withMutation(of: self, keyPath: \.launchAtLogin) {
            storedLaunchAtLogin = settings.launchAtLogin
        }
        registrar.withMutation(of: self, keyPath: \.alwaysHiddenSectionEnabled) {
            storedAlwaysHiddenSectionEnabled = settings.alwaysHiddenSectionEnabled
        }
        registrar.withMutation(of: self, keyPath: \.autoRehideEnabled) {
            storedAutoRehideEnabled = settings.autoRehideEnabled
        }
        registrar.withMutation(of: self, keyPath: \.autoRehideSeconds) {
            storedAutoRehideSeconds = settings.autoRehideSeconds
        }
    }
}
