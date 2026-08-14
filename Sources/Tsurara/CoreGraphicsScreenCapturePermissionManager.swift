import CoreGraphics
import Foundation
import TsuraraCore

/// CoreGraphics の画面収録権限 API を使う具象実装。
///
/// CGPreflightScreenCaptureAccess は「未決定」と「拒否」を区別しないため、
/// リクエスト実行済みかだけを UserDefaults に保存して状態を補完する。
@MainActor
final class CoreGraphicsScreenCapturePermissionManager:
    ScreenCapturePermissionManaging
{
    private enum Key {
        static let hasRequestedAccess = "screenCapturePermission.hasRequestedAccess"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var status: ScreenCapturePermissionStatus {
        if CGPreflightScreenCaptureAccess() {
            return .authorized
        }
        return defaults.bool(forKey: Key.hasRequestedAccess)
            ? .denied
            : .notDetermined
    }

    func requestAccess() -> Bool {
        // API 呼び出し前に記録し、ダイアログ表示中の終了後も再要求しない。
        defaults.set(true, forKey: Key.hasRequestedAccess)
        return CGRequestScreenCaptureAccess()
    }
}
