import CoreGraphics
import Foundation

public enum MenuBarItemClickButton: Equatable, Sendable {
    case left
    case right
}

public enum MenuBarItemClickForwardingState: Equatable, Sendable {
    case idle
    case preparing
    case forwarding
    case waitingForInterfaceDismissal
}

public enum MenuBarItemClickForwardingError: Error, Equatable {
    case operationInProgress
    case windowNotFound(windowID: CGWindowID)
}

/// Core の転送フローから CGEvent の生成・送出を分離する境界。
@MainActor
public protocol MenuBarItemClickSending: AnyObject {
    func sendClick(at point: CGPoint, button: MenuBarItemClickButton) async throws
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
        button: MenuBarItemClickButton
    ) async throws
}

/// サブバーの代理アイコンから実アイテムへクリックを転送する状態機械。
///
/// Ice (jordanbaird/Ice) も、対象を一時的に表示可能な位置へ移し、現在位置へ
/// CGEvent を送り、クリック後に新しく現れた同一 owner のウィンドウが消えるまで
/// 再非表示を遅延させる方式を採っている。Accessibility の AXPress は実装ごとの
/// accessibility tree 品質に左右され、CGWindowID から AXUIElement を一意に得る
/// 公開 API もないため、既に撮像結果が保持する windowID/frame を活用できる同方式を
/// 採用する。
@MainActor
public final class MenuBarItemClickForwardingController:
    MenuBarItemClickForwarding
{
    public private(set) var state: MenuBarItemClickForwardingState = .idle

    private let windowLister: any MenuBarItemWindowListing
    private let positioner: any MenuBarItemCapturePositioning
    private let clickSender: any MenuBarItemClickSending
    private let interfaceTracker: any MenuBarItemInterfaceTracking

    public init(
        windowLister: any MenuBarItemWindowListing,
        positioner: any MenuBarItemCapturePositioning,
        clickSender: any MenuBarItemClickSending,
        interfaceTracker: any MenuBarItemInterfaceTracking
    ) {
        self.windowLister = windowLister
        self.positioner = positioner
        self.clickSender = clickSender
        self.interfaceTracker = interfaceTracker
    }

    public func forwardClick(
        on item: ImagedMenuBarItem,
        button: MenuBarItemClickButton
    ) async throws {
        guard state == .idle else {
            throw MenuBarItemClickForwardingError.operationInProgress
        }

        state = .preparing
        var didReposition = false
        defer {
            if didReposition {
                positioner.restoreAfterCapture()
            }
            state = .idle
        }

        // ImagedMenuBarItem.frame は撮像の一時展開中の座標になり得る。クリック時点の
        // 画面外／画面内判定には使わず、まず WindowServer の現在値を取得する。
        guard let windowBeforeRepositioning = try windowLister
            .listMenuBarItemWindows()
            .first(where: { $0.windowID == item.windowID })
        else {
            throw MenuBarItemClickForwardingError.windowNotFound(
                windowID: item.windowID
            )
        }
        didReposition = positioner.prepareForCapture(
            of: [windowBeforeRepositioning]
        )

        // length の変更有無にかかわらず再列挙し、prepare 後の確定座標へ送る。
        // windowID は同じ WindowServer ウィンドウを追跡する。
        guard let currentWindow = try windowLister.listMenuBarItemWindows()
            .first(where: { $0.windowID == item.windowID })
        else {
            throw MenuBarItemClickForwardingError.windowNotFound(
                windowID: item.windowID
            )
        }

        interfaceTracker.prepareForClick(
            ownerPID: currentWindow.owner.processIdentifier
        )
        state = .forwarding
        try await clickSender.sendClick(
            at: CGPoint(x: currentWindow.frame.midX, y: currentWindow.frame.midY),
            button: button
        )

        state = .waitingForInterfaceDismissal
        try await interfaceTracker.waitUntilInterfaceDismissed()
    }
}
