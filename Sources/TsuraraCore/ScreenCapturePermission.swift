/// 初回リクエストが非同期に決定されるシステム権限の共通状態。
public enum SystemPermissionStatus: Equatable, Sendable {
    case authorized
    case notDetermined
    /// リクエストを以前提示したが、現在の preflight では許可を確認できない。
    /// プロンプトへの回答待ち、拒否、TCC リセット後のいずれも含み得る。
    case requestPreviouslyPresented
}

/// システムへの権限リクエスト直後に判断できる結果。
public enum SystemPermissionRequestResult: Equatable, Sendable {
    case authorized
    /// macOS の権限 API は初回プロンプトへの回答を待たず false を返すため、
    /// false を拒否とは断定せず、後で状態を再確認する。
    case decisionPending
}

/// OS の権限 API を利用側から分離する。
@MainActor
public protocol SystemPermissionManaging: AnyObject {
    var status: SystemPermissionStatus { get }

    /// システムの権限リクエストを表示する。
    @discardableResult
    func requestAccess() -> SystemPermissionRequestResult
}

public typealias ScreenCapturePermissionStatus = SystemPermissionStatus
public typealias ScreenCapturePermissionRequestResult = SystemPermissionRequestResult
public typealias ScreenCapturePermissionManaging = SystemPermissionManaging

/// preflight とリクエスト API を注入可能にし、権限の状態を導出する。
///
/// 対象 API の preflight は未決定と拒否を区別しない。したがって永続フラグは
/// 「提示済み」を表すだけであり、それ単独で拒否済みとは判定しない。
@MainActor
public final class SystemPermissionManager: SystemPermissionManaging {
    private let wasRequestPresented: () -> Bool
    private let setRequestPresented: (Bool) -> Void
    private let preflightAccess: () -> Bool
    private let requestSystemAccess: () -> Bool

    public init(
        wasRequestPresented: @escaping () -> Bool,
        setRequestPresented: @escaping (Bool) -> Void,
        preflightAccess: @escaping () -> Bool,
        requestAccess: @escaping () -> Bool
    ) {
        self.wasRequestPresented = wasRequestPresented
        self.setRequestPresented = setRequestPresented
        self.preflightAccess = preflightAccess
        requestSystemAccess = requestAccess
    }

    public var status: SystemPermissionStatus {
        if preflightAccess() {
            // 実状態を常に優先し、古い提示済みフラグとの乖離を解消する。
            setRequestPresented(false)
            return .authorized
        }
        return wasRequestPresented()
            ? .requestPreviouslyPresented
            : .notDetermined
    }

    public func requestAccess() -> SystemPermissionRequestResult {
        // API が初回プロンプト表示時に即座に false を返しても、次回起動・操作時に
        // 再確認できるよう、呼び出し前に提示済みとして記録する。
        setRequestPresented(true)
        guard requestSystemAccess() else { return .decisionPending }

        setRequestPresented(false)
        return .authorized
    }
}

/// 画面収録権限向けの永続フラグを共通フローへ接続する薄いアダプター。
@MainActor
public final class ScreenCapturePermissionManager: ScreenCapturePermissionManaging {
    private let manager: SystemPermissionManager

    public init(
        settings: SettingsStore,
        preflightAccess: @escaping () -> Bool,
        requestAccess: @escaping () -> Bool
    ) {
        manager = SystemPermissionManager(
            wasRequestPresented: { settings.hasRequestedScreenCaptureAccess },
            setRequestPresented: { settings.hasRequestedScreenCaptureAccess = $0 },
            preflightAccess: preflightAccess,
            requestAccess: requestAccess
        )
    }

    public var status: ScreenCapturePermissionStatus { manager.status }

    public func requestAccess() -> ScreenCapturePermissionRequestResult {
        manager.requestAccess()
    }
}
