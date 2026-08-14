import AppKit
import TsuraraCore

/// length で画面外へ押し出された項目を、撮像中だけ表示可能な位置へ戻す。
@MainActor
final class AppKitMenuBarItemCapturePositioner: MenuBarItemCapturePositioning {
    private let dividerItem: any StatusItem
    private let expandedLength: CGFloat
    private var lengthToRestore: CGFloat?

    init(
        dividerItem: any StatusItem,
        expandedLength: CGFloat = StatusItemLength.square
    ) {
        self.dividerItem = dividerItem
        self.expandedLength = expandedLength
    }

    func prepareForCapture(of windows: [MenuBarItemWindow]) async -> Bool {
        let screenHorizontalRanges = NSScreen.screens.map {
            $0.frame.minX..<$0.frame.maxX
        }
        let containsOffscreenWindow = windows.contains { window in
            !screenHorizontalRanges.contains { range in
                window.frame.maxX > range.lowerBound
                    && window.frame.minX < range.upperBound
            }
        }
        guard containsOffscreenWindow, dividerItem.length != expandedLength else {
            return false
        }

        lengthToRestore = dividerItem.length
        dividerItem.length = expandedLength

        // NSStatusItem.length の変更は WindowServer に非同期で反映される。直後の
        // CGWindowList/ScreenCaptureKit は古い負座標を返すことがあるため、短時間だけ
        // RunLoop を譲り、呼び出し側に再列挙させる。固定待機は撮像時だけで、通常の
        // collapse/expand 操作には影響しない。
        try? await Task.sleep(for: .milliseconds(100))
        return true
    }

    func restoreAfterCapture() {
        guard let lengthToRestore else { return }
        dividerItem.length = lengthToRestore
        self.lengthToRestore = nil
    }
}
