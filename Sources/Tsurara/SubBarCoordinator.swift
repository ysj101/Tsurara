import AppKit
import TsuraraCore

/// 権限確認・撮像と、Core の開閉状態／AppKit パネルを結ぶアプリ層の調停役。
@MainActor
final class SubBarCoordinator {
    private let manager: SectionManager
    private let toggleItem: AppKitStatusItem
    private let imager: MenuBarItemImager
    private let permissionController: ScreenCapturePermissionOnboardingController
    private let presentationController: SubBarPresentationController
    private var captureTask: Task<Void, Never>?

    init(
        manager: SectionManager,
        toggleItem: AppKitStatusItem,
        imager: MenuBarItemImager,
        permissionController: ScreenCapturePermissionOnboardingController,
        presentationController: SubBarPresentationController
    ) {
        self.manager = manager
        self.toggleItem = toggleItem
        self.imager = imager
        self.permissionController = permissionController
        self.presentationController = presentationController
    }

    func toggle() {
        switch presentationController.toggle() {
        case .beginOpening:
            var didPermitOpening = false
            permissionController.openSubBarIfPermitted { [weak self] in
                didPermitOpening = true
                self?.startCapture()
            }
            if !didPermitOpening {
                presentationController.close()
            }
        case .close:
            captureTask?.cancel()
            captureTask = nil
        }
    }

    func close() {
        captureTask?.cancel()
        captureTask = nil
        presentationController.close()
    }

    private func startCapture() {
        captureTask?.cancel()
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { captureTask = nil }
            do {
                guard
                    let mainDivider = manager.hiddenSection.dividerItem as? AppKitStatusItem,
                    let mainDividerWindowID = mainDivider.windowID
                else {
                    presentationController.close()
                    return
                }
                let subDividerWindowID =
                    (manager.alwaysHiddenSection.dividerItem as? AppKitStatusItem)?.windowID
                let items = try await imager.captureHiddenItems(
                    mainDividerWindowID: mainDividerWindowID,
                    subDividerWindowID: subDividerWindowID
                )
                guard !Task.isCancelled,
                      presentationController.state == .opening,
                      let anchorFrame = toggleItem.screenFrame
                else { return }

                presentationController.open(items: items, anchorFrame: anchorFrame)
            } catch is CancellationError {
                presentationController.close()
            } catch {
                presentationController.close()
                if !Task.isCancelled {
                    showCaptureFailure(error)
                }
            }
        }
    }

    private func showCaptureFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "サブバーを表示できませんでした"
        alert.informativeText = "メニューバーアイコンの画像取得に失敗しました。\n\(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private extension AppKitStatusItem {
    var screenFrame: CGRect? {
        guard let button = underlying.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}
