import Foundation
import ServiceManagement
import TsuraraCore

@MainActor
final class SMAppServiceLoginItem: LoginItemManaging {
    private var service: SMAppService { .mainApp }

    /// 「登録済み」の判定。`.requiresApproval` は登録自体は受理されており
    /// システム設定での承認待ちの状態のため、登録済みとして扱う
    /// （false に潰すと、有効化 → 承認待ち → チェックが戻る → 再有効化で
    /// kSMErrorAlreadyRegistered、という復帰不能ループになる）。
    var isRegistered: Bool {
        switch service.status {
        case .enabled, .requiresApproval:
            true
        case .notRegistered, .notFound:
            false
        @unknown default:
            false
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // SMAppServiceErrorDomain の素のエラーは説明が無く行動に繋がらないため、
            // 現在の status の説明を添える（未署名実行 = .notFound など）。
            throw SMAppServiceLoginItemError.operationFailed(
                requestedEnabled: enabled,
                statusDescription: Self.description(of: service.status),
                underlying: error
            )
        }
        // 直後の status 読み取りは servicemanagementd 側の反映遅延で古い値を
        // 返すことがあるため、非スローの register/unregister を成功とみなす。
        // 実状態との照合は次回の sync()（設定画面の onAppear）で行う。
    }

    private static func description(of status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered:
            "未登録"
        case .enabled:
            "有効"
        case .requiresApproval:
            "システム設定 > ログイン項目 での承認待ち"
        case .notFound:
            "アプリバンドルが見つからない（swift run など未署名実行では利用できません。Scripts/make-app.sh で生成した Tsurara.app から起動してください）"
        @unknown default:
            "不明"
        }
    }
}

private enum SMAppServiceLoginItemError: LocalizedError {
    case operationFailed(
        requestedEnabled: Bool,
        statusDescription: String,
        underlying: any Error
    )

    var errorDescription: String? {
        switch self {
        case let .operationFailed(requestedEnabled, statusDescription, underlying):
            let action = requestedEnabled ? "有効化" : "無効化"
            return "ログイン時起動を\(action)できませんでした（現在の状態: \(statusDescription)）。\(underlying.localizedDescription)"
        }
    }
}
