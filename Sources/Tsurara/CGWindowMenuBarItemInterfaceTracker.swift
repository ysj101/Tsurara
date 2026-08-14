import AppKit
import CoreGraphics
import TsuraraCore

/// クリック後に現れるメニュー／ポップオーバーの WindowServer ウィンドウを追跡する。
@MainActor
final class CGWindowMenuBarItemInterfaceTracker: MenuBarItemInterfaceTracking {
    private struct Window: Equatable {
        let id: CGWindowID
        let ownerPID: pid_t
        let layer: Int32
    }

    private var ownerPID: pid_t?
    private var windowIDsBeforeClick: Set<CGWindowID> = []

    func prepareForClick(ownerPID: pid_t) {
        self.ownerPID = ownerPID
        windowIDsBeforeClick = Set(onScreenWindows().map(\.id))
    }

    func waitUntilInterfaceDismissed() async throws {
        guard let ownerPID else { return }
        defer {
            self.ownerPID = nil
            windowIDsBeforeClick = []
        }

        // Ice (jordanbaird/Ice) と同じく、クリック前後の差分から同一 owner の
        // 新規ウィンドウを特定する。NSMenu 通知は他プロセスのメニューには届かず、
        // 固定タイマーでは開いているメニューを途中で隠し得るため、この方法が公開 API
        // だけでメニュー表示中の復元を避けられる最も安定したヒューリスティックとなる。
        let discoveryDeadline = Date().addingTimeInterval(0.75)
        var shownInterface: Window?
        repeat {
            try Task.checkCancellation()
            let candidates = onScreenWindows().filter {
                $0.ownerPID == ownerPID && !windowIDsBeforeClick.contains($0.id)
            }
            shownInterface = candidates.first {
                $0.layer == CGWindowLevelForKey(.popUpMenuWindow)
            } ?? candidates.first {
                $0.layer != CGWindowLevelForKey(.statusWindow)
            }
            if shownInterface == nil {
                try await Task.sleep(for: .milliseconds(50))
            }
        } while shownInterface == nil && Date() < discoveryDeadline

        guard let shownInterface else { return }
        while isShowing(shownInterface) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func isShowing(_ window: Window) -> Bool {
        guard onScreenWindows().contains(where: { $0.id == window.id }) else {
            return false
        }
        if window.layer == CGWindowLevelForKey(.popUpMenuWindow) {
            return true
        }

        // ポップオーバー等は通常レベルのウィンドウになることがある。別アプリへ
        // 切り替えた後まで永続ウィンドウを「メニュー」と誤認し続けないよう、Ice と
        // 同様に owner の active 状態も終了条件へ含める。
        return NSRunningApplication(processIdentifier: window.ownerPID)?.isActive == true
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
                let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.int32Value
            else { return nil }
            return Window(id: id, ownerPID: ownerPID, layer: layer)
        }
    }
}
