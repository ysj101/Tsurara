import AppKit
import TsuraraCore

/// オンボーディングと拒否時フォールバックを AppKit で表示する。
@MainActor
final class ScreenCapturePermissionOnboardingController {
    static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    private let flow: ScreenCapturePermissionFlow

    init(
        permission: any ScreenCapturePermissionManaging =
            CoreGraphicsScreenCapturePermissionManager()
    ) {
        flow = ScreenCapturePermissionFlow(permission: permission)
    }

    /// トグル項目またはホットキーからサブバーを開く直前に呼ぶ。
    /// 権限がない場合は UI のみを表示し、`openSubBar` は実行しない。
    func openSubBarIfPermitted(_ openSubBar: () -> Void) {
        handle(flow.actionForSubBarRequest(), openSubBar: openSubBar)
    }

    private func handle(
        _ action: ScreenCapturePermissionAction,
        openSubBar: () -> Void
    ) {
        switch action {
        case .openSubBar:
            openSubBar()
        case .showOnboarding:
            showOnboarding(openSubBar: openSubBar)
        case .showDeniedFallback:
            showDeniedFallback()
        }
    }

    private func showOnboarding(openSubBar: () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "サブバーには画面収録の許可が必要です"
        alert.informativeText = "Tsurara は、非表示にしたメニューバーアイコンをサブバーに表示するため、メニューバーの画像を取得します。"
        alert.addButton(withTitle: "続ける")
        alert.addButton(withTitle: "今はしない")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        handle(
            flow.requestAccessAfterOnboarding(),
            openSubBar: openSubBar
        )
    }

    private func showDeniedFallback() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "画面収録が許可されていません"
        alert.informativeText = "サブバーは利用できませんが、メニューバーアイコンの非表示機能は引き続き動作します。サブバーを使うには、システム設定で Tsurara の画面収録を許可してください。"
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "キャンセル")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(Self.systemSettingsURL)
    }
}
