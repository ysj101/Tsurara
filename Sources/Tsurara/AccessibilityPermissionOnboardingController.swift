import AppKit
import ApplicationServices
import Foundation
import TsuraraCore

@MainActor
final class SystemAccessibilityPermissionManager: AccessibilityPermissionManaging {
    private enum Key {
        static let hasRequestedAccess = "accessibilityPermission.hasRequestedAccess"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var status: AccessibilityPermissionStatus {
        if AXIsProcessTrusted() {
            return .authorized
        }
        return defaults.bool(forKey: Key.hasRequestedAccess)
            ? .denied
            : .notDetermined
    }

    func requestAccess() -> Bool {
        defaults.set(true, forKey: Key.hasRequestedAccess)
        // kAXTrustedCheckOptionPrompt は SDK 上 mutable global として輸入され、Swift 6
        // の actor 分離から参照できない。公開定数の値を使って同じ options を組む。
        let promptKey = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}

/// 合成クリックだけを Accessibility 権限でガードする AppKit UI。
@MainActor
final class AccessibilityPermissionOnboardingController {
    static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    private let flow: AccessibilityPermissionFlow

    init(
        permission: any AccessibilityPermissionManaging =
            SystemAccessibilityPermissionManager()
    ) {
        flow = AccessibilityPermissionFlow(permission: permission)
    }

    func forwardClickIfPermitted(_ forwardClick: () -> Void) {
        handle(flow.actionForClickRequest(), forwardClick: forwardClick)
    }

    private func handle(
        _ action: AccessibilityPermissionAction,
        forwardClick: () -> Void
    ) {
        switch action {
        case .forwardClick:
            forwardClick()
        case .showOnboarding:
            showOnboarding(forwardClick: forwardClick)
        case .showDeniedFallback:
            showDeniedFallback()
        }
    }

    private func showOnboarding(forwardClick: () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "アイコンの操作にはアクセシビリティの許可が必要です"
        alert.informativeText = "Tsurara は、サブバーで選んだ実際のメニューバーアイコンへクリックを送るためにだけ、この許可を使用します。サブバーの表示は許可しなくても利用できます。"
        alert.addButton(withTitle: "続ける")
        alert.addButton(withTitle: "今はしない")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        handle(flow.requestAccess(), forwardClick: forwardClick)
    }

    private func showDeniedFallback() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "アクセシビリティが許可されていません"
        alert.informativeText = "サブバーは引き続き表示できますが、アイコンのクリック転送は無効です。操作を有効にするには、システム設定で Tsurara を許可してください。"
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "キャンセル")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(Self.systemSettingsURL)
    }
}
