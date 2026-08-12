@MainActor
public protocol LoginItemManaging {
    var isRegistered: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// ログイン項目の実状態と保存済み設定を一致させる。
///
/// `setEnabled` の成否にかかわらずサービスの状態を読み直すため、システム設定で
/// 登録が拒否・解除された場合にも、保存値が実際の状態から乖離しない。
@MainActor
public struct LoginItemSettingsSynchronizer {
    private let settings: SettingsStore
    private let loginItemManager: any LoginItemManaging

    public init(
        settings: SettingsStore,
        loginItemManager: any LoginItemManaging
    ) {
        self.settings = settings
        self.loginItemManager = loginItemManager
    }

    @discardableResult
    public func sync() -> Bool {
        let isRegistered = loginItemManager.isRegistered
        settings.launchAtLogin = isRegistered
        return isRegistered
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) throws -> Bool {
        do {
            try loginItemManager.setEnabled(enabled)
            return sync()
        } catch {
            // register/unregister が途中まで状態を変えてから失敗する可能性もあるため、
            // エラーを返す前に必ず現在の status を保存する。
            _ = sync()
            throw error
        }
    }
}
