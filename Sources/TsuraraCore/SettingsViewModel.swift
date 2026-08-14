import Observation

public final class SettingsViewModel: Observable {
    private let settings: SettingsStore
    private let registrar = ObservationRegistrar()
    private var storedLaunchAtLogin: Bool
    private var storedAlwaysHiddenSectionEnabled: Bool
    private var storedAutoCloseEnabled: Bool
    private var storedAutoCloseSeconds: Int

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

    public var autoCloseEnabled: Bool {
        get {
            registrar.access(self, keyPath: \.autoCloseEnabled)
            return storedAutoCloseEnabled
        }
        set {
            registrar.withMutation(of: self, keyPath: \.autoCloseEnabled) {
                storedAutoCloseEnabled = newValue
                settings.autoCloseEnabled = newValue
            }
        }
    }

    public var autoCloseSeconds: Int {
        get {
            registrar.access(self, keyPath: \.autoCloseSeconds)
            return storedAutoCloseSeconds
        }
        set {
            registrar.withMutation(of: self, keyPath: \.autoCloseSeconds) {
                settings.autoCloseSeconds = newValue
                // SettingsStore remains the source of truth for range enforcement.
                storedAutoCloseSeconds = settings.autoCloseSeconds
            }
        }
    }

    public init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        storedLaunchAtLogin = settings.launchAtLogin
        storedAlwaysHiddenSectionEnabled = settings.alwaysHiddenSectionEnabled
        storedAutoCloseEnabled = settings.autoCloseEnabled
        storedAutoCloseSeconds = settings.autoCloseSeconds
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
        registrar.withMutation(of: self, keyPath: \.autoCloseEnabled) {
            storedAutoCloseEnabled = settings.autoCloseEnabled
        }
        registrar.withMutation(of: self, keyPath: \.autoCloseSeconds) {
            storedAutoCloseSeconds = settings.autoCloseSeconds
        }
    }
}
