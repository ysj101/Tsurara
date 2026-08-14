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
        case let .beginOpening(generation):
            var didPermitOpening = false
            permissionController.openSubBarIfPermitted { [weak self] in
                didPermitOpening = true
                self?.startCapture(generation: generation)
            }
            if !didPermitOpening {
                presentationController.close(generation: generation)
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

    private func startCapture(generation: SubBarPresentationController.Generation) {
        captureTask?.cancel()
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Task はキャンセル用ハンドルであり、進行状態は controller の世代付き
            // state だけを正とする。古い Task が新しい Task の参照を消してはならない。
            defer {
                if presentationController.isLatestGeneration(generation) {
                    captureTask = nil
                }
            }
            do {
                guard
                    let mainDivider = manager.hiddenSection.dividerItem as? AppKitStatusItem,
                    let mainDividerWindowID = mainDivider.windowID
                else {
                    presentationController.close(generation: generation)
                    return
                }
                let subDividerWindowID =
                    (manager.alwaysHiddenSection.dividerItem as? AppKitStatusItem)?.windowID
                let items = try await imager.captureHiddenItems(
                    mainDividerWindowID: mainDividerWindowID,
                    subDividerWindowID: subDividerWindowID
                )
                guard !Task.isCancelled else { return }
                guard presentationController.ownsCycle(generation) else { return }

                presentationController.open(
                    items: items,
                    generation: generation,
                    anchorFrame: { [weak toggleItem] in toggleItem?.screenFrame }
                )
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                presentationController.close(generation: generation)
            } catch {
                guard !Task.isCancelled,
                      presentationController.ownsCycle(generation)
                else { return }
                presentationController.close(generation: generation)
                showCaptureFailure(error)
            }
        }
    }

    private func showCaptureFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "サブバーを表示できませんでした"
        alert.informativeText = "メニューバーアイコンの画像取得に失敗しました。\n\(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private extension AppKitStatusItem {
    var screenFrame: CGRect? {
        guard let button = underlying.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}
