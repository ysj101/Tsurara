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
    private let clickForwarder: any MenuBarItemClickForwarding
    private let accessibilityPermissionController:
        AccessibilityPermissionOnboardingController
    private var captureTask: Task<Void, Never>?
    private var forwardingTask: Task<Void, Never>?

    init(
        manager: SectionManager,
        toggleItem: AppKitStatusItem,
        imager: MenuBarItemImager,
        permissionController: ScreenCapturePermissionOnboardingController,
        presentationController: SubBarPresentationController,
        clickForwarder: any MenuBarItemClickForwarding,
        accessibilityPermissionController:
            AccessibilityPermissionOnboardingController
    ) {
        self.manager = manager
        self.toggleItem = toggleItem
        self.imager = imager
        self.permissionController = permissionController
        self.presentationController = presentationController
        self.clickForwarder = clickForwarder
        self.accessibilityPermissionController = accessibilityPermissionController
    }

    func toggle() {
        forwardingTask?.cancel()
        switch presentationController.toggle() {
        case let .beginOpening(generation):
            var didPermitOpening = false
            permissionController.openSubBarIfPermitted { [weak self] in
                didPermitOpening = true
                self?.startCapture(generation: generation)
            }
            if !didPermitOpening {
                closeSubBar(generation: generation)
            }
        case .close:
            closeSubBar()
        }
    }

    func close() {
        closeSubBar()
    }

    @discardableResult
    private func closeSubBar(
        generation: SubBarPresentationController.Generation? = nil,
        cancelCapture: Bool = true
    ) -> Bool {
        if cancelCapture {
            captureTask?.cancel()
            captureTask = nil
        }
        forwardingTask?.cancel()
        let didClose: Bool
        if let generation {
            didClose = presentationController.close(generation: generation)
        } else {
            presentationController.close()
            didClose = true
        }
        if didClose {
            manager.setSubBarOpen(false)
        }
        return didClose
    }

    func forwardClick(
        on item: ImagedMenuBarItem,
        button: MenuBarItemClickButton
    ) {
        accessibilityPermissionController.forwardClickIfPermitted {
            [weak self] in
            self?.startForwardingClick(on: item, button: button)
        }
    }

    private func startForwardingClick(
        on item: ImagedMenuBarItem,
        button: MenuBarItemClickButton
    ) {
        guard forwardingTask == nil else { return }
        // 実アイテムのメニューとパネルが重ならないよう、許可済みの場合だけ閉じる。
        // 権限がない経路ではサブバーを表示したままにし、クリック転送だけを無効化する。
        closeSubBar()
        manager.beginAutoClosePause(source: .clickForwarding)
        forwardingTask = Task { @MainActor [weak self, manager] in
            defer { manager.endAutoClosePause(source: .clickForwarding) }
            guard let self else { return }
            defer {
                forwardingTask = nil
            }
            do {
                try await clickForwarder.forwardClick(on: item, button: button)
            } catch is CancellationError {
                // Core 側の defer が区切りを復元する。終了時の警告は不要。
            } catch {
                showForwardingFailure(error)
            }
        }
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
                    closeSubBar(generation: generation, cancelCapture: false)
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

                let didOpen = presentationController.open(
                    items: items,
                    generation: generation,
                    anchorFrame: { [weak toggleItem] in toggleItem?.screenFrame }
                )
                manager.setSubBarOpen(didOpen)
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                closeSubBar(generation: generation, cancelCapture: false)
            } catch {
                guard !Task.isCancelled,
                      presentationController.ownsCycle(generation)
                else { return }
                closeSubBar(generation: generation, cancelCapture: false)
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

    private func showForwardingFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "アイコンを操作できませんでした"
        alert.informativeText = "実際のメニューバーアイコンへのクリック転送に失敗しました。\n\(error.localizedDescription)"
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
