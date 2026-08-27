import CoreGraphics
import Foundation
import TsuraraCore

/// クリック後に現れるメニュー／ポップオーバーの WindowServer ウィンドウを追跡する。
@MainActor
final class CGWindowMenuBarItemInterfaceTracker: MenuBarItemInterfaceTracking {
    private struct Window: Equatable {
        let id: CGWindowID
        let ownerPID: pid_t
        let layer: Int32
        let frame: CGRect
    }

    private var windowIDsBeforeClick: Set<CGWindowID> = []

    func prepareForClick() {
        windowIDsBeforeClick = Set(onScreenWindows().map(\.id))
    }

    func waitUntilInterfaceDismissed(ownerPID: pid_t) async throws {
        defer {
            windowIDsBeforeClick = []
        }

        // Ice (jordanbaird/Ice) と同じく、クリック前後の差分から同一 owner の
        // 新規ウィンドウを特定する。NSMenu 通知は他プロセスのメニューには届かず、
        // 固定タイマーでは開いているメニューを途中で隠し得るため、この方法が公開 API
        // だけでメニュー表示中の復元を避けられる最も安定したヒューリスティックとなる。
        let waitDeadline = ContinuousClock.now.advanced(by: .seconds(60))
        let discoveryDeadline = ContinuousClock.now.advanced(by: .milliseconds(750))
        var shownInterface: Window?
        repeat {
            try Task.checkCancellation()
            let candidates = onScreenWindows().filter {
                $0.ownerPID == ownerPID
                    && !windowIDsBeforeClick.contains($0.id)
                    && isPlausibleInterface($0)
            }
            shownInterface = candidates.first {
                $0.layer == CGWindowLevelForKey(.popUpMenuWindow)
            } ?? candidates.first {
                $0.layer >= CGWindowLevelForKey(.normalWindow)
                    && $0.layer < CGWindowLevelForKey(.statusWindow)
            }
            let allNew = onScreenWindows().filter { !windowIDsBeforeClick.contains($0.id) }
            if !allNew.isEmpty {
            }
            if shownInterface == nil {
                try await Task.sleep(for: .milliseconds(50))
            }
        } while shownInterface == nil && ContinuousClock.now < discoveryDeadline

        guard let shownInterface else { return }
        var pollInterval = Duration.milliseconds(100)
        while windowExists(id: shownInterface.id) {
            try Task.checkCancellation()
            guard ContinuousClock.now < waitDeadline else { return }
            try await Task.sleep(for: pollInterval)
            pollInterval = min(pollInterval * 2, .seconds(1))
        }
    }

    private func isPlausibleInterface(_ window: Window) -> Bool {
        let size = window.frame.size
        guard size.width >= 20, size.height >= 20,
              size.width <= 1_600, size.height <= 1_600
        else { return false }
        return window.layer != CGWindowLevelForKey(.statusWindow)
    }

    /// 追跡対象が決まった後は全ウィンドウを再列挙せず、その ID だけを照会する。
    /// LSUIElement アプリでは isActive がメニュー／ポップオーバーの存続を表さないため、
    /// WindowServer 上から実際に消えることだけを終了条件にする。
    private func windowExists(id: CGWindowID) -> Bool {
        let ids = [NSNumber(value: id)] as CFArray
        guard let descriptions = CGWindowListCreateDescriptionFromArray(ids)
            as? [[String: Any]]
        else { return false }
        return !descriptions.isEmpty
    }

    private func onScreenWindows() -> [Window] {
        guard let dictionaries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return dictionaries.compactMap { dictionary in
            guard
                let id = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let ownerPID = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.int32Value,
                let bounds = dictionary[kCGWindowBounds as String]
                    as? [String: NSNumber],
                let frame = CGRect(
                    dictionaryRepresentation: bounds as CFDictionary
                )
            else { return nil }
            return Window(id: id, ownerPID: ownerPID, layer: layer, frame: frame)
        }
    }
}
