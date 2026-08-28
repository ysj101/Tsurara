import CoreGraphics
import Foundation
import TsuraraCore

/// CGEventCreateMouseEvent 相当の Swift API で実アイテム位置へ down/up を送る。
@MainActor
final class CoreGraphicsMenuBarItemClickSender: MenuBarItemClickSending {
    func sendClick(
        at point: CGPoint,
        button: MenuBarItemClickButton,
        ownerPID: pid_t,
        windowID: CGWindowID
    ) async throws {
        let eventTypes: (down: CGEventType, up: CGEventType, mouse: CGMouseButton)
        switch button {
        case .left:
            eventTypes = (.leftMouseDown, .leftMouseUp, .left)
        case .right:
            eventTypes = (.rightMouseDown, .rightMouseUp, .right)
        }

        let pair = try CoreGraphicsMenuBarItemEventSupport.makeMousePair(
            at: point,
            downType: eventTypes.down,
            upType: eventTypes.up,
            button: eventTypes.mouse
        )

        for event in [pair.down, pair.up] {
            CoreGraphicsMenuBarItemEventSupport.configure(
                event,
                ownerPID: ownerPID,
                windowID: windowID,
                flags: [],
                clickState: 1
            )
        }

        CoreGraphicsMenuBarItemEventSupport.permitLocalEventsDuringSuppression()
        let originalCursorPosition =
            CoreGraphicsMenuBarItemEventSupport.hideCursorSavingPosition()
        defer {
            CoreGraphicsMenuBarItemEventSupport.restoreCursor(
                to: originalCursorPosition
            )
        }

        let buttonKind = switch button {
        case .left: "left"
        case .right: "right"
        }
        NSLog(
            "クリック転送: button=%@ windowID=%u pid=%d point=(%.1f, %.1f)",
            buttonKind,
            windowID,
            ownerPID,
            point.x,
            point.y
        )

        // postToPid は WindowServer のヒットテストを経由しないため、宛先フィールドを
        // 設定しても実際の配送には結びつかない。同じ OS 制約下で成功している Ice と
        // 同様に session tap へ投稿し、移動する実カーソルは投稿中だけ隠して元の位置へ戻す。
        try await CoreGraphicsMenuBarItemEventSupport.postPair(pair)
    }

}
