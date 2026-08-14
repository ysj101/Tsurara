import CoreGraphics
import TsuraraCore

/// Core の権限管理へ CoreGraphics API を注入するアプリ用アダプター。
@MainActor
final class CoreGraphicsScreenCapturePermissionManager:
    ScreenCapturePermissionManaging
{
    static let shared = CoreGraphicsScreenCapturePermissionManager()

    private let manager: ScreenCapturePermissionManager

    init(settings: SettingsStore = SettingsStore()) {
        manager = ScreenCapturePermissionManager(
            settings: settings,
            preflightAccess: { CGPreflightScreenCaptureAccess() },
            requestAccess: { CGRequestScreenCaptureAccess() }
        )
    }

    var status: ScreenCapturePermissionStatus {
        manager.status
    }

    func requestAccess() -> ScreenCapturePermissionRequestResult {
        manager.requestAccess()
    }
}
