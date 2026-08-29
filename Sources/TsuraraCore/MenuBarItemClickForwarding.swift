import CoreGraphics
import Foundation

public enum MenuBarItemClickButton: Equatable, Sendable {
    case left
    case right
}

public enum MenuBarItemClickForwardingError: Error, Equatable, LocalizedError {
    case itemNotFound(ownerPID: pid_t)
    case itemRestorationFailed(ownerPID: pid_t)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            "実際のメニューバーアイコンを見つけられませんでした。"
        case .itemRestorationFailed:
            "アイコンを元の位置に戻せませんでした。Cmd を押しながらドラッグして戻してください。"
        }
    }
}

/// 移動先は AppKit 由来の座標だけでも表現できる。自プロセスの status-level
/// window が列挙されない OS では ID を省略し、投稿時に移動対象の ID を代用する。
public enum MenuBarItemMoveDestination: Equatable, Sendable {
    case leftOf(anchorFrame: CGRect, anchorWindowID: CGWindowID?)
    case rightOf(anchorFrame: CGRect, anchorWindowID: CGWindowID?)

    public var anchorWindowID: CGWindowID? {
        switch self {
        case let .leftOf(_, windowID), let .rightOf(_, windowID): windowID
        }
    }

    public func isSatisfied(
        by itemFrame: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        let gap = switch self {
        case let .leftOf(anchorFrame, _):
            anchorFrame.minX - itemFrame.maxX
        case let .rightOf(anchorFrame, _):
            itemFrame.minX - anchorFrame.maxX
        }
        // WindowServer の再配置では数 pt 重なることがあるが、反対側へ回った項目を
        // 大きな tolerance だけで到着扱いにしてはならない。
        let overlapTolerance: CGFloat = 8
        return gap >= -overlapTolerance && gap <= tolerance
    }
}

/// move が throw した時点で、イベントが投稿済みかを Core へ明示する。
public enum MenuBarItemMoveFailure: Error {
    case notMoved(any Error)
    case indeterminate(any Error)
}

public struct MenuBarItemReturnAnchors: Equatable, Sendable {
    public let right: CGWindowID?
    public let left: CGWindowID?
    public let mainDividerFrame: CGRect

    public init(
        right: CGWindowID?,
        left: CGWindowID?,
        mainDividerFrame: CGRect
    ) {
        self.right = right
        self.left = left
        self.mainDividerFrame = mainDividerFrame
    }

    public static func computing(
        for target: MenuBarItemWindow,
        in sectionWindows: [MenuBarItemWindow],
        mainDividerFrame: CGRect
    ) -> Self {
        let ordered = sectionWindows.sorted(by: MenuBarItemWindow.isOrderedBefore)
        let index = ordered.firstIndex { $0.windowID == target.windowID }
        let right = index.flatMap { index in
            ordered.indices.contains(index + 1) ? ordered[index + 1].windowID : nil
        }
        let left = index.flatMap { index in
            index > ordered.startIndex ? ordered[index - 1].windowID : nil
        }
        return Self(right: right, left: left, mainDividerFrame: mainDividerFrame)
    }

    public func destination(
        currentWindows: [MenuBarItemWindow]
    ) -> MenuBarItemMoveDestination {
        if let right,
           let window = currentWindows.first(where: { $0.windowID == right }) {
            return .leftOf(anchorFrame: window.frame, anchorWindowID: window.windowID)
        }
        if let left,
           let window = currentWindows.first(where: { $0.windowID == left }) {
            return .rightOf(anchorFrame: window.frame, anchorWindowID: window.windowID)
        }
        return .leftOf(anchorFrame: mainDividerFrame, anchorWindowID: nil)
    }
}

/// Core の一時表示トランザクションから、OS 固有の Cmd+移動を分離する境界。
@MainActor
public protocol MenuBarItemMoving: AnyObject {
    func move(
        _ item: MenuBarItemWindow,
        to destination: MenuBarItemMoveDestination,
        in windows: [MenuBarItemWindow]?
    ) async throws(MenuBarItemMoveFailure) -> MenuBarItemWindow
}

public extension MenuBarItemMoving {
    func move(
        _ item: MenuBarItemWindow,
        to destination: MenuBarItemMoveDestination
    ) async throws(MenuBarItemMoveFailure) -> MenuBarItemWindow {
        try await move(item, to: destination, in: nil)
    }
}

/// Core の転送フローから CGEvent の生成・送出を分離する境界。
@MainActor
public protocol MenuBarItemClickSending: AnyObject {
    func sendClick(
        at point: CGPoint,
        button: MenuBarItemClickButton,
        ownerPID: pid_t,
        windowID: CGWindowID
    ) async throws
}

/// 実座標から AX 要素を解決して押す経路。合成イベントより優先する。
@MainActor
public protocol MenuBarItemAccessibilityActivating: AnyObject {
    /// 押せた場合に、解決できた実際の所有プロセスを返す。押せなければ nil。
    func activate(
        at point: CGPoint,
        itemFrame: CGRect,
        button: MenuBarItemClickButton
    ) async throws -> pid_t?
}

/// クリックで現れたメニュー／ポップオーバーの終了待ちを OS 実装から分離する境界。
@MainActor
public protocol MenuBarItemInterfaceTracking: AnyObject {
    func prepareForClick()
    func waitUntilInterfaceDismissed(ownerPID: pid_t) async throws
}

@MainActor
public protocol MenuBarItemClickForwarding: AnyObject {
    func forwardClick(
        on item: ImagedMenuBarItem,
        button: MenuBarItemClickButton,
        mainDividerFrame: CGRect,
        subDividerFrame: CGRect?,
        toggleFrame: CGRect?,
        displayFrames: [CGRect]
    ) async throws
}

/// サブバーの代理アイコンから実アイテムへクリックを転送する状態機械。
/// 項目移動を使えない場合だけ従来の length 展開へ戻し、移動を開始した可能性が
/// ある場合はクリック成否やキャンセルにかかわらず復帰を最優先する。
@MainActor
public final class MenuBarItemClickForwardingController: MenuBarItemClickForwarding {
    private let windowLister: any MenuBarItemWindowListing
    private let positioner: any MenuBarItemCapturePositioning
    private let clickSender: any MenuBarItemClickSending
    private let interfaceTracker: any MenuBarItemInterfaceTracking
    private let activator: (any MenuBarItemAccessibilityActivating)?
    private let mover: (any MenuBarItemMoving)?
    private let repositionWaiter: MenuBarItemRepositionWaiter
    private let restorationAttemptLimit: Int
    private let restorationRetryDelay: Duration

    public init(
        windowLister: any MenuBarItemWindowListing,
        positioner: any MenuBarItemCapturePositioning,
        clickSender: any MenuBarItemClickSending,
        interfaceTracker: any MenuBarItemInterfaceTracking,
        activator: (any MenuBarItemAccessibilityActivating)? = nil,
        mover: (any MenuBarItemMoving)? = nil,
        repositionPollInterval: Duration = .milliseconds(20),
        repositionPollLimit: Int = 25,
        restorationAttemptLimit: Int = 3,
        restorationRetryDelay: Duration = .milliseconds(100)
    ) {
        self.windowLister = windowLister
        self.positioner = positioner
        self.clickSender = clickSender
        self.interfaceTracker = interfaceTracker
        self.activator = activator
        self.mover = mover
        self.restorationAttemptLimit = max(1, restorationAttemptLimit)
        self.restorationRetryDelay = restorationRetryDelay
        self.repositionWaiter = MenuBarItemRepositionWaiter(
            windowLister: windowLister,
            pollInterval: repositionPollInterval,
            pollLimit: repositionPollLimit
        )
    }

    public func forwardClick(
        on item: ImagedMenuBarItem,
        button: MenuBarItemClickButton,
        mainDividerFrame: CGRect,
        subDividerFrame: CGRect?,
        toggleFrame: CGRect?,
        displayFrames: [CGRect]
    ) async throws {
        let listedWindows = try windowLister.listMenuBarItemWindows()
        let sectionWindows = MenuBarItemSectionGeometry.hiddenWindows(
            in: listedWindows,
            mainDividerFrame: mainDividerFrame,
            subDividerFrame: subDividerFrame,
            displayFrames: displayFrames
        )
        guard let target = closestWindow(
            to: item.sourceFrame,
            ownerPID: item.owner.processIdentifier,
            title: item.title,
            preferredOrder: item.order,
            in: sectionWindows
        ) else {
            throw MenuBarItemClickForwardingError.itemNotFound(
                ownerPID: item.owner.processIdentifier
            )
        }

        guard let mover, let toggleFrame else {
            return try await forwardUsingCaptureExpansion(
                item: item,
                button: button,
                target: target,
                listedWindows: listedWindows
            )
        }

        let returnAnchors = MenuBarItemReturnAnchors.computing(
            for: target,
            in: sectionWindows,
            mainDividerFrame: mainDividerFrame
        )
        let temporaryDestination = MenuBarItemMoveDestination.leftOf(
            anchorFrame: toggleFrame,
            anchorWindowID: nil
        )
        let movedWindow: MenuBarItemWindow
        do {
            movedWindow = try await mover.move(
                target,
                to: temporaryDestination,
                in: listedWindows
            )
        } catch let failure {
            switch failure {
            case .notMoved:
                return try await forwardUsingCaptureExpansion(
                    item: item,
                    button: button,
                    target: target,
                    listedWindows: listedWindows
                )
            case let .indeterminate(error):
                // キャンセルを含め、投稿後の失敗はクリックへ進めず復帰だけを行う。
                guard await restore(
                    target: target,
                    anchors: returnAnchors,
                    mover: mover,
                    settlingFrom: target.frame
                ) else {
                    throw MenuBarItemClickForwardingError.itemRestorationFailed(
                        ownerPID: target.owner.processIdentifier
                    )
                }
                throw error
            }
        }

        return try await forwardMovedItem(
            target: target,
            movedWindow: movedWindow,
            button: button,
            returnAnchors: returnAnchors,
            mover: mover,
            displayFrames: displayFrames
        )
    }

    private func forwardUsingCaptureExpansion(
        item: ImagedMenuBarItem,
        button: MenuBarItemClickButton,
        target: MenuBarItemWindow,
        listedWindows: [MenuBarItemWindow]
    ) async throws {
        var didReposition = false
        defer {
            if didReposition {
                positioner.restoreAfterCapture()
            }
        }

        // length 展開は同一ソース内の並びを変えない。この経路だけは展開前の
        // ソース内 index で、windowID が更新された項目を安全に対応付けられる。
        let sourceWindowsBeforeRepositioning = sourceWindows(
            ownerPID: item.owner.processIdentifier,
            title: item.title,
            in: listedWindows
        )
        guard let indexAmongSourceItems = sourceWindowsBeforeRepositioning
            .firstIndex(where: { $0.windowID == target.windowID })
        else {
            throw MenuBarItemClickForwardingError.itemNotFound(
                ownerPID: item.owner.processIdentifier
            )
        }
        didReposition = positioner.prepareForCapture(of: [target])

        let currentWindow: MenuBarItemWindow
        if didReposition {
            let readyWindow = try await repositionWaiter.waitUntilReady(
                resolvingWindow: { windows in
                    let sourceWindows = self.sourceWindows(
                        ownerPID: item.owner.processIdentifier,
                        title: item.title,
                        in: windows
                    )
                    guard sourceWindows.indices.contains(indexAmongSourceItems) else {
                        return nil
                    }
                    return sourceWindows[indexAmongSourceItems]
                },
                isReady: positioner.isReadyForCapture
            )
            guard let readyWindow else {
                throw MenuBarItemClickForwardingError.itemNotFound(
                    ownerPID: item.owner.processIdentifier
                )
            }
            currentWindow = readyWindow
        } else {
            currentWindow = target
        }

        try await activateAndWait(on: currentWindow, button: button)
    }

    private func forwardMovedItem(
        target: MenuBarItemWindow,
        movedWindow: MenuBarItemWindow,
        button: MenuBarItemClickButton,
        returnAnchors: MenuBarItemReturnAnchors,
        mover: any MenuBarItemMoving,
        displayFrames: [CGRect]
    ) async throws {
        let forwardingError: (any Error)?
        do {
            guard movedWindow.isVisibleOnMenuBar(displayFrames: displayFrames) else {
                throw MenuBarItemClickForwardingError.itemNotFound(
                    ownerPID: target.owner.processIdentifier
                )
            }
            try await activateAndWait(on: movedWindow, button: button)
            forwardingError = nil
        } catch {
            forwardingError = error
        }

        guard await restore(target: target, anchors: returnAnchors, mover: mover) else {
            throw MenuBarItemClickForwardingError.itemRestorationFailed(
                ownerPID: target.owner.processIdentifier
            )
        }
        if let forwardingError {
            throw forwardingError
        }
    }

    private func restore(
        target: MenuBarItemWindow,
        anchors: MenuBarItemReturnAnchors,
        mover: any MenuBarItemMoving,
        settlingFrom frameBeforeMoving: CGRect? = nil
    ) async -> Bool {
        // 親 Task のキャンセル状態を継承しない Task で、復帰に必要な値だけを保持する。
        await Task { @MainActor [
            windowLister,
            mover,
            target,
            anchors,
            frameBeforeMoving,
            repositionWaiter,
            attemptLimit = restorationAttemptLimit,
            retryDelay = restorationRetryDelay
        ] in
            if let frameBeforeMoving {
                // 投稿直後は古い bounds が返ることがある。保留中の move-out が
                // 反映されるか有界時間だけ待ち、復帰済みとの誤判定を避ける。
                _ = try? await repositionWaiter.waitUntilReady(
                    resolvingWindow: { windows in
                        windows.first { $0.windowID == target.windowID }
                    },
                    isReady: { $0.frame != frameBeforeMoving }
                )
            }
            for attempt in 0..<attemptLimit {
                let windows = (try? windowLister.listMenuBarItemWindows()) ?? []
                do {
                    _ = try await mover.move(
                        target,
                        to: anchors.destination(currentWindows: windows),
                        in: windows
                    )
                    return true
                } catch {
                    if attempt + 1 < attemptLimit {
                        try? await Task.sleep(for: retryDelay)
                    }
                }
            }
            return false
        }.value
    }

    private func activateAndWait(
        on window: MenuBarItemWindow,
        button: MenuBarItemClickButton
    ) async throws {
        let point = CGPoint(x: window.frame.midX, y: window.frame.midY)
        interfaceTracker.prepareForClick()
        let ownerPID: pid_t
        if let activatedOwnerPID = try await activator?.activate(
            at: point,
            itemFrame: window.frame,
            button: button
        ) {
            ownerPID = activatedOwnerPID
        } else {
            try await clickSender.sendClick(
                at: point,
                button: button,
                ownerPID: window.owner.processIdentifier,
                windowID: window.windowID
            )
            ownerPID = window.owner.processIdentifier
        }
        try await interfaceTracker.waitUntilInterfaceDismissed(ownerPID: ownerPID)
    }

    private func closestWindow(
        to frame: CGRect,
        ownerPID: pid_t,
        title: String?,
        preferredOrder: Int,
        in windows: [MenuBarItemWindow]
    ) -> MenuBarItemWindow? {
        // preferredOrder はセクション全体での並び位置なので、候補を絞った後も
        // offset はセクション全体の並びで数える。
        let candidateIDs = Set(
            sourceWindows(ownerPID: ownerPID, title: title, in: windows)
                .map(\.windowID)
        )
        return windows
            .sorted(by: MenuBarItemWindow.isOrderedBefore)
            .enumerated()
            .filter { candidateIDs.contains($0.element.windowID) }
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
            }?.element
    }

    /// 同一ソース（同じアプリ由来）とみなす候補を、メニューバーの並び順で返す。
    private func sourceWindows(
        ownerPID: pid_t,
        title: String?,
        in windows: [MenuBarItemWindow]
    ) -> [MenuBarItemWindow] {
        let ownerWindows = windows.filter {
            $0.owner.processIdentifier == ownerPID
        }
        let titleMatchingWindows = ownerWindows.filter { $0.title == title }

        // 権限変更などで title が取得できなくなった場合は、従来どおり owner PID で対応付ける。
        return (titleMatchingWindows.isEmpty ? ownerWindows : titleMatchingWindows)
            .sorted(by: MenuBarItemWindow.isOrderedBefore)
    }

    private func geometryDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let dx = lhs.midX - rhs.midX
        let dy = lhs.midY - rhs.midY
        let dw = lhs.width - rhs.width
        let dh = lhs.height - rhs.height
        return dx * dx + dy * dy + dw * dw + dh * dh
    }
}
