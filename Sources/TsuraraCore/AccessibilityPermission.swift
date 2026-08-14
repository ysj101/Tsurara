/// 合成クリックに必要なアクセシビリティ権限の状態。
public enum AccessibilityPermissionStatus: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
}

/// macOS の Accessibility API を Core のフロー制御から分離する。
@MainActor
public protocol AccessibilityPermissionManaging: AnyObject {
    var status: AccessibilityPermissionStatus { get }

    @discardableResult
    func requestAccess() -> Bool
}

public enum AccessibilityPermissionAction: Equatable, Sendable {
    case forwardClick
    case showOnboarding
    case showDeniedFallback
}

/// サブバー表示ではなく、実アイテムへの合成クリックだけを権限でガードする。
@MainActor
public struct AccessibilityPermissionFlow {
    private let permission: any AccessibilityPermissionManaging

    public init(permission: any AccessibilityPermissionManaging) {
        self.permission = permission
    }

    public func actionForClickRequest() -> AccessibilityPermissionAction {
        switch permission.status {
        case .authorized:
            return .forwardClick
        case .notDetermined:
            return .showOnboarding
        case .denied:
            return .showDeniedFallback
        }
    }

    public func requestAccess() -> AccessibilityPermissionAction {
        permission.requestAccess() ? .forwardClick : .showDeniedFallback
    }
}
