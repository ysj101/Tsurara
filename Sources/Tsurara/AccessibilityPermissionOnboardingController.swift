import AppKit
import ApplicationServices
import Foundation
import TsuraraCore

@MainActor
final class SystemAccessibilityPermissionManager: AccessibilityPermissionManaging {
    private let manager: AccessibilityPermissionManager

    init(settings: SettingsStore = SettingsStore()) {
        manager = AccessibilityPermissionManager(
            settings: settings,
            preflightAccess: { AXIsProcessTrusted() },
            requestAccess: {
                // kAXTrustedCheckOptionPrompt は SDK 上 mutable global として輸入され、
                // Swift 6 の actor 分離から参照できないため公開定数の値を使う。
                let promptKey = "AXTrustedCheckOptionPrompt"
                return AXIsProcessTrustedWithOptions(
                    [promptKey: true] as CFDictionary
                )
            }
        )
    }

    var status: AccessibilityPermissionStatus {
        manager.status
    }

    func requestAccess() -> AccessibilityPermissionRequestResult {
        manager.requestAccess()
    }
}

/// 合成クリックだけを Accessibility 権限でガードする AppKit UI。
@MainActor
final class AccessibilityPermissionOnboardingController {
    static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    private let permission: any AccessibilityPermissionManaging
    private var isPresentingAlert = false

    init(
        permission: any AccessibilityPermissionManaging =
            SystemAccessibilityPermissionManager()
    ) {
        self.permission = permission
    }

    func forwardClickIfPermitted(_ forwardClick: () -> Void) {
        switch permission.status {
        case .authorized:
            forwardClick()
        case .notDetermined:
            showOnboarding(forwardClick: forwardClick)
        case .requestPreviouslyPresented:
            showPermissionFallback(forwardClick: forwardClick)
        }
    }

    private func showOnboarding(forwardClick: () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "アイコンの操作にはアクセシビリティの許可が必要です"
        alert.informativeText = "Tsurara は、サブバーで選んだ実際のメニューバーアイコンへクリックを送るためにだけ、この許可を使用します。サブバーの表示は許可しなくても利用できます。"
        alert.addButton(withTitle: "続ける")
        alert.addButton(withTitle: "今はしない")

        guard runModal(alert) == .alertFirstButtonReturn else { return }
        // AXIsProcessTrustedWithOptions も初回プロンプトへの回答を待たず false を
        // 返す。システムプロンプトの上へ拒否アラートを重ねず、次回に再確認する。
        if permission.requestAccess() == .authorized {
            forwardClick()
        }
    }

    private func showPermissionFallback(forwardClick: () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "アクセシビリティの許可を確認できません"
        alert.informativeText = "サブバーは引き続き表示できますが、アイコンのクリック転送は無効です。システム設定で Tsurara を許可するか、権限をもう一度リクエストしてください。"
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "権限を再リクエスト")
        alert.addButton(withTitle: "キャンセル")

        switch runModal(alert) {
        case .alertFirstButtonReturn:
            guard NSWorkspace.shared.open(Self.systemSettingsURL) else {
                NSLog(
                    "アクセシビリティのシステム設定を開けませんでした: %@",
                    Self.systemSettingsURL.absoluteString
                )
                return
            }
        case .alertSecondButtonReturn:
            if permission.requestAccess() == .authorized {
                forwardClick()
            }
        default:
            break
        }
    }

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
