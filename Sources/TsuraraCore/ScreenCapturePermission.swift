/// 画面収録権限の状態。
public enum ScreenCapturePermissionStatus: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
}

/// OS の画面収録権限 API を Core のフロー制御から分離する。
@MainActor
public protocol ScreenCapturePermissionManaging: AnyObject {
    var status: ScreenCapturePermissionStatus { get }

    /// システムの権限リクエストを表示し、許可された場合に true を返す。
    @discardableResult
    func requestAccess() -> Bool
}

/// サブバー利用要求に対して UI 層が行うべき処理。
public enum ScreenCapturePermissionAction: Equatable, Sendable {
    case openSubBar
    case showOnboarding
    case showDeniedFallback
}

/// サブバーだけを権限でガードするフロー。
///
/// SectionManager の length 押し出しには関与しないため、権限がない場合も
/// 非表示機能は継続する。UI 層はサブバーを開く直前にこの型へ問い合わせる。
@MainActor
public struct ScreenCapturePermissionFlow {
    private let permission: any ScreenCapturePermissionManaging

    public init(permission: any ScreenCapturePermissionManaging) {
        self.permission = permission
    }

    public func actionForSubBarRequest() -> ScreenCapturePermissionAction {
        switch permission.status {
        case .authorized:
            return .openSubBar
        case .notDetermined:
            return .showOnboarding
        case .denied:
            return .showDeniedFallback
        }
    }

    /// アプリ内の説明を利用者が確認した後にだけ呼び出す。
    public func requestAccessAfterOnboarding() -> ScreenCapturePermissionAction {
        permission.requestAccess() ? .openSubBar : .showDeniedFallback
    }
}
