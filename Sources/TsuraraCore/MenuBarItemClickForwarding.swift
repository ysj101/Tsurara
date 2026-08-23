import CoreGraphics
import Foundation

public enum MenuBarItemClickButton: Equatable, Sendable {
    case left
    case right
}

public enum MenuBarItemClickForwardingError: Error, Equatable {
    case itemNotFound(ownerPID: pid_t)
}

/// Core の転送フローから CGEvent の生成・送出を分離する境界。
@MainActor
public protocol MenuBarItemClickSending: AnyObject {
    func sendClick(
        at point: CGPoint,
        button: MenuBarItemClickButton,
        ownerPID: pid_t
    ) async throws
}

/// クリックで現れたメニュー／ポップオーバーの終了待ちを OS 実装から分離する境界。
@MainActor
public protocol MenuBarItemInterfaceTracking: AnyObject {
    /// クリック前のウィンドウ集合を記録する。
    func prepareForClick(ownerPID: pid_t)
    func waitUntilInterfaceDismissed() async throws
}

@MainActor
public protocol MenuBarItemClickForwarding: AnyObject {
    func forwardClick(
        on item: ImagedMenuBarItem,
        button: MenuBarItemClickButton,
        mainDividerFrame: CGRect,
        subDividerFrame: CGRect?,
        displayFrames: [CGRect]
    ) async throws
}

/// サブバーの代理アイコンから実アイテムへクリックを転送する状態機械。
///
/// Ice (jordanbaird/Ice) も、対象を一時的に表示可能な位置へ移し、現在位置へ
/// CGEvent を送り、クリック後に新しく現れた同一 owner のウィンドウが消えるまで
/// 再非表示を遅延させる方式を採っている。Accessibility の AXPress は実装ごとの
/// accessibility tree 品質に左右され、CGWindowID から AXUIElement を一意に得る
/// 公開 API もないため、展開前は区切り座標・owner・撮像時 frame、展開後は同一
/// owner 内の並び順で対象を再特定し、現在位置へ CGEvent を送る方式を採用する。
@MainActor
public final class MenuBarItemClickForwardingController:
    MenuBarItemClickForwarding
{
    private let windowLister: any MenuBarItemWindowListing
    private let positioner: any MenuBarItemCapturePositioning
    private let clickSender: any MenuBarItemClickSending
    private let interfaceTracker: any MenuBarItemInterfaceTracking
    private let repositionWaiter: MenuBarItemRepositionWaiter

    public init(
        windowLister: any MenuBarItemWindowListing,
        positioner: any MenuBarItemCapturePositioning,
        clickSender: any MenuBarItemClickSending,
        interfaceTracker: any MenuBarItemInterfaceTracking,
        repositionPollInterval: Duration = .milliseconds(20),
        repositionPollLimit: Int = 25
    ) {
        self.windowLister = windowLister
        self.positioner = positioner
        self.clickSender = clickSender
        self.interfaceTracker = interfaceTracker
        self.repositionWaiter = MenuBarItemRepositionWaiter(
            windowLister: windowLister,
            positioner: positioner,
            pollInterval: repositionPollInterval,
            pollLimit: repositionPollLimit
        )
    }

    public func forwardClick(
        on item: ImagedMenuBarItem,
        button: MenuBarItemClickButton,
        mainDividerFrame: CGRect,
        subDividerFrame: CGRect?,
        displayFrames: [CGRect]
    ) async throws {
        var didReposition = false
        defer {
            if didReposition {
                positioner.restoreAfterCapture()
            }
        }

        // sourceFrame は撮像対象を列挙した時点の実座標。同じ区切り条件で現在の
        // hidden セクションを作り、owner と幾何距離で対象を再特定する。
        let listedWindows = try windowLister.listMenuBarItemWindows()
        let sectionWindows = MenuBarItemSectionGeometry.hiddenWindows(
            in: listedWindows,
            mainDividerFrame: mainDividerFrame,
            subDividerFrame: subDividerFrame,
            displayFrames: displayFrames
        )
        guard let windowBeforeRepositioning = closestWindow(
            to: item.sourceFrame,
            ownerPID: item.owner.processIdentifier,
            preferredOrder: item.order,
            in: sectionWindows
        )
        else {
            throw MenuBarItemClickForwardingError.itemNotFound(
                ownerPID: item.owner.processIdentifier
            )
        }
        let ownerWindowsBeforeRepositioning = ownerWindows(
            ownerPID: item.owner.processIdentifier,
            in: sectionWindows
        )
        guard let indexAmongOwnerItems = ownerWindowsBeforeRepositioning
            .firstIndex(where: { $0.windowID == windowBeforeRepositioning.windowID })
        else {
            throw MenuBarItemClickForwardingError.itemNotFound(
                ownerPID: item.owner.processIdentifier
            )
        }
        didReposition = positioner.prepareForCapture(
            of: [windowBeforeRepositioning]
        )

        // 一時展開しなかった場合は初回列挙を再利用する。展開した場合だけ再列挙を
        // 繰り返す。一時展開は同一 owner の項目群の相対順序を変えないため、
        // 展開前と同じ owner 内 index を選べば、座標や windowID の継続性に
        // 依存せず決定的に同じ項目へ対応付けられる。
        let currentWindow: MenuBarItemWindow
        if didReposition {
            let readyWindow = try await repositionWaiter.waitUntilReady { windows in
                let ownerWindows = self.ownerWindows(
                    ownerPID: item.owner.processIdentifier,
                    in: windows
                )
                guard ownerWindows.indices.contains(indexAmongOwnerItems) else {
                    return nil
                }
                return ownerWindows[indexAmongOwnerItems]
            }
            guard let refreshedWindow = readyWindow else {
                // stale frame への CGEvent は別の項目を誤操作し得るため、
                // 再特定できない場合と同じ itemNotFound として安全に中止する。
                throw MenuBarItemClickForwardingError.itemNotFound(
                    ownerPID: item.owner.processIdentifier
                )
            }
            currentWindow = refreshedWindow
        } else {
            currentWindow = windowBeforeRepositioning
        }

        interfaceTracker.prepareForClick(
            ownerPID: currentWindow.owner.processIdentifier
        )
        try await clickSender.sendClick(
            at: CGPoint(x: currentWindow.frame.midX, y: currentWindow.frame.midY),
            button: button,
            ownerPID: currentWindow.owner.processIdentifier
        )

        try await interfaceTracker.waitUntilInterfaceDismissed()
    }

    private func closestWindow(
        to frame: CGRect,
        ownerPID: pid_t,
        preferredOrder: Int,
        in windows: [MenuBarItemWindow]
    ) -> MenuBarItemWindow? {
        // 同一 owner の複数項目が幾何的に等距離でも、撮像時の相対順序で
        // 同じ項目を選び、最後は windowID で結果を決定的にする。
        let closest = windows
            .sorted {
                if $0.frame.minX == $1.frame.minX {
                    return $0.windowID < $1.windowID
                }
                return $0.frame.minX < $1.frame.minX
            }
            .enumerated()
            .filter { $0.element.owner.processIdentifier == ownerPID }
            .min { lhs, rhs in
                let lhsDistance = geometryDistance(lhs.element.frame, frame)
                let rhsDistance = geometryDistance(rhs.element.frame, frame)
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }

                let lhsOrderDistance = abs(lhs.offset - preferredOrder)
                let rhsOrderDistance = abs(rhs.offset - preferredOrder)
                if lhsOrderDistance != rhsOrderDistance {
                    return lhsOrderDistance < rhsOrderDistance
                }
                return lhs.element.windowID < rhs.element.windowID
            }
        return closest?.element
    }

    private func ownerWindows(
        ownerPID: pid_t,
        in windows: [MenuBarItemWindow]
    ) -> [MenuBarItemWindow] {
        windows
            .filter { $0.owner.processIdentifier == ownerPID }
            .sorted {
                if $0.frame.minX == $1.frame.minX {
                    return $0.windowID < $1.windowID
                }
                return $0.frame.minX < $1.frame.minX
            }
    }

    private func geometryDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let dx = lhs.midX - rhs.midX
        let dy = lhs.midY - rhs.midY
        let dw = lhs.width - rhs.width
        let dh = lhs.height - rhs.height
        return dx * dx + dy * dy + dw * dw + dh * dh
    }
}
