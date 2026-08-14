/// 画面収録権限の状態。
public enum ScreenCapturePermissionStatus: Equatable, Sendable {
    case authorized
    case notDetermined
    /// リクエストを以前提示したが、現在の preflight では許可を確認できない。
    /// プロンプトへの回答待ち、拒否、TCC リセット後のいずれも含み得る。
    case requestPreviouslyPresented
}

/// システムへの権限リクエスト直後に判断できる結果。
public enum ScreenCapturePermissionRequestResult: Equatable, Sendable {
    case authorized
    /// CoreGraphics の API は初回プロンプトへの回答を待たず false を返すため、
    /// false を拒否とは断定せず、後で状態を再確認する。
    case decisionPending
}

/// OS の画面収録権限 API を利用側から分離する。
@MainActor
public protocol ScreenCapturePermissionManaging: AnyObject {
    var status: ScreenCapturePermissionStatus { get }

    /// システムの権限リクエストを表示する。
    @discardableResult
    func requestAccess() -> ScreenCapturePermissionRequestResult
}

/// preflight とリクエスト API を注入可能にし、画面収録権限の状態を導出する。
///
/// CoreGraphics の preflight は未決定と拒否を区別しない。したがって永続フラグは
/// 「提示済み」を表すだけであり、それ単独で拒否済みとは判定しない。
@MainActor
public final class ScreenCapturePermissionManager: ScreenCapturePermissionManaging {
    private let settings: SettingsStore
    private let preflightAccess: () -> Bool
    private let requestSystemAccess: () -> Bool

    public init(
        settings: SettingsStore,
        preflightAccess: @escaping () -> Bool,
        requestAccess: @escaping () -> Bool
    ) {
        self.settings = settings
        self.preflightAccess = preflightAccess
        requestSystemAccess = requestAccess
    }

    public var status: ScreenCapturePermissionStatus {
        if preflightAccess() {
            // 実状態を常に優先し、古い提示済みフラグとの乖離を解消する。
            settings.hasRequestedScreenCaptureAccess = false
            return .authorized
        }
        return settings.hasRequestedScreenCaptureAccess
            ? .requestPreviouslyPresented
            : .notDetermined
    }

    public func requestAccess() -> ScreenCapturePermissionRequestResult {
        // API が初回プロンプト表示時に即座に false を返しても、次回起動・操作時に
        // 再確認できるよう、呼び出し前に提示済みとして記録する。
        settings.hasRequestedScreenCaptureAccess = true
        guard requestSystemAccess() else { return .decisionPending }

        settings.hasRequestedScreenCaptureAccess = false
        return .authorized
    }
}
