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

    /// 公開の CGEventField には無い、AppKit が宛先ウィンドウ番号として読む値。
    /// jordanbaird/Ice も公開フィールドと併せてこの 0x33 に同じ値を入れている。
    private static let windowNumberEventField = CGEventField(rawValue: 0x33)

    private func configure(
        events: [CGEvent],
        ownerPID: pid_t,
        windowID: CGWindowID
    ) {
        // postToPid は WindowServer のヒットテストを経ないため、宛先 PID だけでは
        // NSEvent の windowNumber が決まらない。対象ウィンドウも明示して配送する。
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
