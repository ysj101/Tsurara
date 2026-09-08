import AppKit
import Foundation
import TsuraraCore

enum MenuBarItemPlacementMoveOutcome {
    case moved(MenuBarItemPlacement)
    case notPermitted
    case failed(any Error)
}

/// 設定画面の配置操作と、メニューバーの実座標・権限確認を接続する調停役。
@MainActor
final class MenuBarItemPlacementCoordinator {
    private let manager: SectionManager
    private let controller: MenuBarItemPlacementController
    private let permissionController: AccessibilityPermissionOnboardingController
    private let isSubBarBusy: () -> Bool

    init(
        manager: SectionManager,
        controller: MenuBarItemPlacementController,
        permissionController: AccessibilityPermissionOnboardingController,
        isSubBarBusy: @escaping () -> Bool
    ) {
        self.manager = manager
        self.controller = controller
        self.permissionController = permissionController
        self.isSubBarBusy = isSubBarBusy
    }

    /// Tsurara 自身の status item は WindowServer 上で別 PID に見えることがあるため、
    /// PID ではなく AppKit の矩形と autosaveName の両方で除外する。
    func list() throws -> [MenuBarItemPlacement] {
        guard let mainDivider = manager.hiddenSection.dividerItem as? DividerFrameProviding,
              let mainFrame = mainDivider.dividerFrame else {
            throw MenuBarItemPlacementError.mainDividerUnavailable
        }
        let subFrame =
            (manager.alwaysHiddenSection.dividerItem as? DividerFrameProviding)?.dividerFrame
        let toggleFrame = (manager.toggleItem as? DividerFrameProviding)?.dividerFrame
        let excludedFrames = [toggleFrame, mainFrame, subFrame].compactMap { $0 }
        let excludedTitles: Set<String> = [
            SectionManager.toggleItemIdentifier,
            SectionManager.mainDividerIdentifier,
            SectionManager.subDividerIdentifier
        ]
        return try controller.listPlacements(
            mainDividerFrame: mainFrame,
            subDividerFrame: subFrame,
            displayFrames: AppKitScreenGeometry.cgFrames,
            excludedFrames: excludedFrames,
            excludedTitles: excludedTitles
        )
    }

    func move(
        _ item: MenuBarItemPlacement,
        to section: MenuBarSectionKind,
        completion: @escaping @MainActor (MenuBarItemPlacementMoveOutcome) -> Void
    ) {
        guard !isSubBarBusy() else {
            completion(.failed(MenuBarItemPlacementError.subBarBusy))
            return
        }
        var didPermit = false
        permissionController.forwardClickIfPermitted { [self] in
            didPermit = true
            manager.onSubBarCloseRequested?()
            Task { @MainActor in
                do {
                    let placement = try await controller.move(
                        item.window,
                        to: section,
                        mainDividerFrame: { [manager] in
                            (manager.hiddenSection.dividerItem as? DividerFrameProviding)?.dividerFrame
                        },
                        subDividerFrame:
                            (manager.alwaysHiddenSection.dividerItem as? DividerFrameProviding)?.dividerFrame,
                        displayFrames: AppKitScreenGeometry.cgFrames
                    )
                    completion(.moved(placement))
                } catch {
                    NSLog("項目の配置移動に失敗: %@", String(describing: error))
                    completion(.failed(error))
                }
            }
        }
        if !didPermit {
            completion(.notPermitted)
        }
    }
}
