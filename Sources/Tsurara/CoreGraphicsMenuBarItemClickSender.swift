import CoreGraphics
import Foundation
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
        ownerPID: pid_t,
        windowID: CGWindowID
    ) async throws {
        // hidSystemState を使いつつ、下で flags を空にして実修飾状態の継承を打ち消す。
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

        configure(
            events: [mouseDown, mouseUp],
            ownerPID: ownerPID,
            windowID: windowID
        )

        Self.permitLocalEventsDuringSuppression()

        let originalCursorPosition = CGEvent(source: nil)?.location
        CGDisplayHideCursor(CGMainDisplayID())
        defer {
            if let originalCursorPosition {
                CGWarpMouseCursorPosition(originalCursorPosition)
            }
            CGDisplayShowCursor(CGMainDisplayID())
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
        mouseDown.post(tap: .cgSessionEventTap)
        defer {
            // sleep のキャンセルも含め、down を送った全経路で必ず up を対にする。
            mouseUp.post(tap: .cgSessionEventTap)
        }
        // down/up を同一 run-loop tick に詰めると一部の常駐アプリが up を落とすため、
        // 人間のクリックより十分短い間隔だけ空ける。
        try await Task.sleep(for: .milliseconds(25))
    }

    /// 公開の CGEventField には無い、AppKit が宛先ウィンドウ番号として読む値。
    /// jordanbaird/Ice も公開フィールドと併せてこの 0x33 に同じ値を入れている。
    private static let windowNumberEventField = CGEventField(rawValue: 0x33)

    private static func permitLocalEventsDuringSuppression() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        let permitAllEvents: CGEventFilterMask = [
            .permitLocalMouseEvents,
            .permitLocalKeyboardEvents,
            .permitSystemDefinedEvents,
        ]
        source.setLocalEventsFilterDuringSuppressionState(
            permitAllEvents,
            state: .eventSuppressionStateRemoteMouseDrag
        )
        source.setLocalEventsFilterDuringSuppressionState(
            permitAllEvents,
            state: .eventSuppressionStateSuppressionInterval
        )
        source.localEventsSuppressionInterval = 0
    }

    private func configure(
        events: [CGEvent],
        ownerPID: pid_t,
        windowID: CGWindowID
    ) {
        // session tap で WindowServer が対象を特定できるよう、PID と対象ウィンドウを
        // 宛先フィールドに明示する。
        for event in events {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(
                .eventTargetUnixProcessID,
                value: Int64(ownerPID)
            )
            event.setIntegerValueField(
                .mouseEventWindowUnderMousePointer,
                value: Int64(windowID)
            )
            event.setIntegerValueField(
                .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
                value: Int64(windowID)
            )
            if let windowNumberEventField = Self.windowNumberEventField {
                event.setIntegerValueField(
                    windowNumberEventField,
                    value: Int64(windowID)
                )
            }
            // control+クリックを右クリックへ変換した後も maskControl を残さない。
            event.flags = []
        }
    }
}
