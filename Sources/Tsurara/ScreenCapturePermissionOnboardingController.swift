import AppKit
import TsuraraCore

/// オンボーディングと拒否時フォールバックを AppKit で表示する。
@MainActor
final class ScreenCapturePermissionOnboardingController {
    static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    private let permission: any ScreenCapturePermissionManaging
    private var isPresentingAlert = false

    init(
        permission: any ScreenCapturePermissionManaging =
            CoreGraphicsScreenCapturePermissionManager.shared
    ) {
        self.permission = permission
    }

    /// トグル項目またはホットキーからサブバーを開く直前に呼ぶ。
    /// 権限がない場合は UI のみを表示し、`openSubBar` は実行しない。
    func openSubBarIfPermitted(_ openSubBar: () -> Void) {
        switch permission.status {
        case .authorized:
            openSubBar()
        case .notDetermined:
            showOnboarding(openSubBar: openSubBar)
        case .requestPreviouslyPresented:
            showPermissionFallback(openSubBar: openSubBar)
        }
    }

    private func showOnboarding(openSubBar: () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "サブバーには画面収録の許可が必要です"
        alert.informativeText = "Tsurara は、非表示にしたメニューバーアイコンをサブバーに表示するため、メニューバーの画像を取得します。許可後も反映されない場合は、Tsurara を再起動してください。"
        alert.addButton(withTitle: "続ける")
        alert.addButton(withTitle: "今はしない")

        guard runModal(alert) == .alertFirstButtonReturn else { return }
        // 初回はシステムプロンプトへの回答を待たず decisionPending になる。
        // ここで別のアラートを重ねず、次回の操作時に preflight を再確認する。
        if permission.requestAccess() == .authorized {
            openSubBar()
        }
    }

    private func showPermissionFallback(openSubBar: () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "画面収録の許可を確認できません"
        alert.informativeText = "サブバーは利用できませんが、メニューバーアイコンの非表示機能は引き続き動作します。システム設定で Tsurara を許可するか、権限をもう一度リクエストしてください。許可後も反映されない場合は、Tsurara を再起動してください。"
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "権限を再リクエスト")
        alert.addButton(withTitle: "キャンセル")

        switch runModal(alert) {
        case .alertFirstButtonReturn:
            guard NSWorkspace.shared.open(Self.systemSettingsURL) else {
                NSLog(
                    "画面収録のシステム設定を開けませんでした: %@",
                    Self.systemSettingsURL.absoluteString
                )
                return
            }
        case .alertSecondButtonReturn:
            // 拒否済みなら無害に false、TCC リセット後なら再びプロンプトを
            // 提示できる。false 直後にフォールバックを再表示しない。
            if permission.requestAccess() == .authorized {
                openSubBar()
            }
        default:
            break
        }
    }

    /// accessory アプリが一時的に奪ったフォーカスをモーダル終了後に戻す。
    /// 同時に複数経路から呼ばれても runModal を重ねない。
    private func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse? {
        guard !isPresentingAlert else { return nil }
        isPresentingAlert = true
        let shouldDeactivateAfterward = !NSApp.isActive
        defer {
            isPresentingAlert = false
            if shouldDeactivateAfterward {
                NSApp.deactivate()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
