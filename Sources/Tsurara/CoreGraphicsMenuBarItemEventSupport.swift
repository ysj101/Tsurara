import CoreGraphics
import Foundation

enum CoreGraphicsMenuBarItemEventError: Error {
    case eventSourceCreationFailed
    case eventCreationFailed
}

/// クリックと Cmd+移動が WindowServer へ渡すイベントの共通設定。
enum CoreGraphicsMenuBarItemEventSupport {
    struct MousePair {
        let down: CGEvent
        let up: CGEvent
    }

    /// 公開 API にない AppKit の宛先 window number。
    private static let windowNumberEventField = CGEventField(rawValue: 0x33)

    static func makeMousePair(
        at point: CGPoint,
        downType: CGEventType,
        upType: CGEventType,
        button: CGMouseButton
    ) throws -> MousePair {
        // hidSystemState を使いつつ、呼び出し側で flags を明示して実修飾状態の
        // 継承を打ち消す。
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw CoreGraphicsMenuBarItemEventError.eventSourceCreationFailed
        }
        guard
            let down = CGEvent(
                mouseEventSource: source,
                mouseType: downType,
                mouseCursorPosition: point,
                mouseButton: button
            ),
            let up = CGEvent(
                mouseEventSource: source,
                mouseType: upType,
                mouseCursorPosition: point,
                mouseButton: button
            )
        else {
            throw CoreGraphicsMenuBarItemEventError.eventCreationFailed
        }
        return MousePair(down: down, up: up)
    }

    static func postPair(_ pair: MousePair) async throws {
        pair.down.post(tap: .cgSessionEventTap)
        defer {
            // sleep のキャンセルも含め、down を送った全経路で必ず up を対にする。
            pair.up.post(tap: .cgSessionEventTap)
        }
        // down/up を同一 run-loop tick に詰めると一部の常駐アプリが up を落とすため、
        // 人間のクリックより十分短い間隔だけ空ける。
        try await Task.sleep(for: .milliseconds(25))
    }

    static func configure(
        _ event: CGEvent,
        ownerPID: pid_t,
        windowID: CGWindowID,
        flags: CGEventFlags,
        clickState: Int64? = nil
    ) {
        if let clickState {
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
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
        if let windowNumberEventField {
            event.setIntegerValueField(
                windowNumberEventField,
                value: Int64(windowID)
            )
        }
        event.flags = flags
    }

    static func permitLocalEventsDuringSuppression() {
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

    static func hideCursorSavingPosition() -> CGPoint? {
        let position = CGEvent(source: nil)?.location
        CGDisplayHideCursor(CGMainDisplayID())
        return position
    }

    static func restoreCursor(to position: CGPoint?) {
        if let position {
            CGWarpMouseCursorPosition(position)
        }
        CGDisplayShowCursor(CGMainDisplayID())
    }
}
