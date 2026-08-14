/// Accessibility と画面収録は、どちらもシステム API が初回プロンプトへの
/// 回答を待たず false を返す。同じ pending 状態機械を共有し、false を拒否と
/// 誤判定しない。
public typealias AccessibilityPermissionStatus = SystemPermissionStatus
public typealias AccessibilityPermissionRequestResult = SystemPermissionRequestResult
public typealias AccessibilityPermissionManaging = SystemPermissionManaging

@MainActor
public final class AccessibilityPermissionManager: AccessibilityPermissionManaging {
    private let manager: SystemPermissionManager

    public init(
        settings: SettingsStore,
        preflightAccess: @escaping () -> Bool,
        requestAccess: @escaping () -> Bool
    ) {
        manager = SystemPermissionManager(
            wasRequestPresented: { settings.hasRequestedAccessibilityAccess },
            setRequestPresented: { settings.hasRequestedAccessibilityAccess = $0 },
            preflightAccess: preflightAccess,
            requestAccess: requestAccess
        )
    }

    public var status: AccessibilityPermissionStatus { manager.status }

    public func requestAccess() -> AccessibilityPermissionRequestResult {
        manager.requestAccess()
    }
}
