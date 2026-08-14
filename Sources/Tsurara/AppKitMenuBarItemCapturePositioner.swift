import AppKit
import TsuraraCore

/// length で画面外へ押し出された項目を、撮像中だけ表示可能な位置へ戻す。
@MainActor
final class AppKitMenuBarItemCapturePositioner: MenuBarItemCapturePositioning {
    private let sectionManager: SectionManager
    private let screenFrames: () -> [CGRect]
    private var ownsCaptureExpansion = false

    init(
        sectionManager: SectionManager,
        screenFrames: (() -> [CGRect])? = nil
    ) {
        self.sectionManager = sectionManager
        self.screenFrames = screenFrames ?? Self.cgScreenFrames
    }

    func prepareForCapture(of windows: [MenuBarItemWindow]) -> Bool {
        guard windows.contains(where: { !isVisibleOnMenuBar($0) }) else { return false }
        ownsCaptureExpansion = sectionManager.beginCaptureExpansion()
        return ownsCaptureExpansion
    }

    func isReadyForCapture(_ window: MenuBarItemWindow) -> Bool {
        isVisibleOnMenuBar(window)
    }

    func restoreAfterCapture() {
        guard ownsCaptureExpansion else { return }
        sectionManager.endCaptureExpansion()
        ownsCaptureExpansion = false
    }

    private func isVisibleOnMenuBar(_ window: MenuBarItemWindow) -> Bool {
        window.isVisibleOnMenuBar(displayFrames: screenFrames())
    }

    /// NSScreen は左下原点、CGWindow は主画面左上原点なので y を反転する。
    private static func cgScreenFrames() -> [CGRect] {
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return [] }
        return NSScreen.screens.map { screen in
            CGRect(
                x: screen.frame.minX,
                y: primaryMaxY - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
        }
    }
}
