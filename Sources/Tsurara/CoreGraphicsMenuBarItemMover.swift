import CoreGraphics
import Foundation
import TsuraraCore

enum CoreGraphicsMenuBarItemMoveError: Error {
    case itemWindowNotFound
    case moveTimedOut
}

/// 1 回分の Cmd+移動を担当する。再試行と復帰アンカーの選択は、ユーザー配置を
/// 把握している Core のトランザクションだけが所有する。
@MainActor
final class CoreGraphicsMenuBarItemMover: MenuBarItemMoving {
    private let windowLister: any MenuBarItemWindowListing
    private let pollInterval: Duration
    private let pollLimit: Int
    private let destinationTolerance: CGFloat

    init(
        windowLister: any MenuBarItemWindowListing,
        pollInterval: Duration = .milliseconds(10),
        pollLimit: Int = 25,
        destinationTolerance: CGFloat = 300
    ) {
        self.windowLister = windowLister
        self.pollInterval = pollInterval
        self.pollLimit = max(1, pollLimit)
        self.destinationTolerance = max(0, destinationTolerance)
    }

    func move(
        _ item: MenuBarItemWindow,
        to destination: MenuBarItemMoveDestination,
        in windows: [MenuBarItemWindow]? = nil
    ) async throws(MenuBarItemMoveFailure) -> MenuBarItemWindow {
        let currentItem: MenuBarItemWindow
        let pair: CoreGraphicsMenuBarItemEventSupport.MousePair
        do {
            try Task.checkCancellation()
            let currentWindows = try windows
                ?? windowLister.listMenuBarItemWindows()
            guard var current = currentWindows.first(where: {
                $0.windowID == item.windowID
            }) else {
                throw CoreGraphicsMenuBarItemMoveError.itemWindowNotFound
            }
            if arrivedWindow(
                windowID: item.windowID,
                destination: destination,
                in: currentWindows
            ) != nil {
                // move-out 直後の復帰では古い bounds が一度だけ見えることがある。
                // イベントを省略する早期成功だけは、次の列挙でも同じ側にいることを確認する。
                try await Task.sleep(for: pollInterval)
                try Task.checkCancellation()
                let confirmedWindows = try windowLister.listMenuBarItemWindows()
                if let confirmed = arrivedWindow(
                    windowID: item.windowID,
                    destination: destination,
                    in: confirmedWindows
                ) {
                    return confirmed
                }
                guard let confirmed = confirmedWindows.first(where: {
                    $0.windowID == item.windowID
                }) else {
                    throw CoreGraphicsMenuBarItemMoveError.itemWindowNotFound
                }
                current = confirmed
            }
            currentItem = current
            let point = targetPoint(for: destination)
            pair = try CoreGraphicsMenuBarItemEventSupport.makeMousePair(
                at: point,
                downType: .leftMouseDown,
                upType: .leftMouseUp,
                button: .left
            )
            try Task.checkCancellation()
        } catch {
            throw .notMoved(error)
        }

        CoreGraphicsMenuBarItemEventSupport.configure(
            pair.down,
            ownerPID: currentItem.owner.processIdentifier,
            windowID: currentItem.windowID,
            flags: .maskCommand
        )
        CoreGraphicsMenuBarItemEventSupport.configure(
            pair.up,
            ownerPID: currentItem.owner.processIdentifier,
            windowID: destination.anchorWindowID ?? currentItem.windowID,
            flags: []
        )
        CoreGraphicsMenuBarItemEventSupport.permitLocalEventsDuringSuppression()

        let originalCursorPosition =
            CoreGraphicsMenuBarItemEventSupport.hideCursorSavingPosition()
        defer {
            CoreGraphicsMenuBarItemEventSupport.restoreCursor(
                to: originalCursorPosition
            )
        }

        NSLog(
            "項目移動: windowID=%u anchorID=%u point=(%.1f, %.1f)",
            currentItem.windowID,
            destination.anchorWindowID ?? currentItem.windowID,
            pair.down.location.x,
            pair.down.location.y
        )
        do {
            try await CoreGraphicsMenuBarItemEventSupport.postPair(pair)
        } catch {
            // postPair は中断時にも up を送るが、down 後なので移動成否は不明となる。
            throw .indeterminate(error)
        }

        do {
            for _ in 0..<pollLimit {
                // 投稿直後の古い snapshot を成功判定に使わないよう、先に待つ。
                try await Task.sleep(for: pollInterval)
                try Task.checkCancellation()
                if let arrived = arrivedWindow(
                    windowID: currentItem.windowID,
                    destination: destination,
                    in: try windowLister.listMenuBarItemWindows()
                ) {
                    return arrived
                }
            }
            throw CoreGraphicsMenuBarItemMoveError.moveTimedOut
        } catch {
            throw .indeterminate(error)
        }
    }

    private func arrivedWindow(
        windowID: CGWindowID,
        destination: MenuBarItemMoveDestination,
        in windows: [MenuBarItemWindow]
    ) -> MenuBarItemWindow? {
        guard let current = windows.first(where: { $0.windowID == windowID }),
              destination.isSatisfied(
                  by: current.frame,
                  tolerance: destinationTolerance
              )
        else { return nil }
        return current
    }

    private func targetPoint(
        for destination: MenuBarItemMoveDestination
    ) -> CGPoint {
        let point = switch destination {
        case let .leftOf(anchorFrame, _):
            CGPoint(x: anchorFrame.minX - 1, y: anchorFrame.midY)
        case let .rightOf(anchorFrame, _):
            CGPoint(x: anchorFrame.maxX + 1, y: anchorFrame.midY)
        }
        // minY は矩形の排他的な上端として bounds 外になる実装がある。
        return point
    }
}
