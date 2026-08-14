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
        button: MenuBarItemClickButton
    ) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
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
        mouseDown.post(tap: .cghidEventTap)
        // down/up を同一 run-loop tick に詰めると一部の常駐アプリが up を落とすため、
        // 人間のクリックより十分短い間隔だけ空ける。
        try await Task.sleep(for: .milliseconds(10))
        mouseUp.post(tap: .cghidEventTap)
    }
}
