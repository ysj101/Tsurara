import CoreGraphics
import TsuraraCore

enum CoreGraphicsMenuBarItemClickError: Error {
    case eventSourceCreationFailed
    case eventCreationFailed
}

/// CGEventCreateMouseEvent 相当の Swift API で実アイテム位置へ down/up を送る。
@MainActor
final class CoreGraphicsMenuBarItemClickSender: MenuBarItemClickSending {
    func sendClick(
        at point: CGPoint,
        button: MenuBarItemClickButton,
        ownerPID: pid_t
    ) async throws {
        // privateState を使い、生成時点の実キーボード修飾状態を継承しない。
        guard let source = CGEventSource(stateID: .privateState) else {
            throw CoreGraphicsMenuBarItemClickError.eventSourceCreationFailed
        }

        let eventTypes: (down: CGEventType, up: CGEventType, mouse: CGMouseButton)
        switch button {
        case .left:
            eventTypes = (.leftMouseDown, .leftMouseUp, .left)
        case .right:
            eventTypes = (.rightMouseDown, .rightMouseUp, .right)
        }

        guard
            let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: eventTypes.down,
                mouseCursorPosition: point,
                mouseButton: eventTypes.mouse
            ),
            let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: eventTypes.up,
                mouseCursorPosition: point,
                mouseButton: eventTypes.mouse
            )
        else {
            throw CoreGraphicsMenuBarItemClickError.eventCreationFailed
        }

        mouseDown.setIntegerValueField(.mouseEventClickState, value: 1)
        mouseUp.setIntegerValueField(.mouseEventClickState, value: 1)
        // control+クリックを右クリックへ変換した後も maskControl を残さない。
        mouseDown.flags = []
        mouseUp.flags = []

        // HID tap への投稿は実カーソルを対象座標へワープさせる。対象プロセスへ
        // 直接配送すれば、他プロセスと実カーソルへ副作用を広げずに済む。
        mouseDown.postToPid(ownerPID)
        defer {
            // sleep のキャンセルも含め、down を送った全経路で必ず up を対にする。
            mouseUp.postToPid(ownerPID)
        }
        // down/up を同一 run-loop tick に詰めると一部の常駐アプリが up を落とすため、
        // 人間のクリックより十分短い間隔だけ空ける。
        try await Task.sleep(for: .milliseconds(10))
    }
}
