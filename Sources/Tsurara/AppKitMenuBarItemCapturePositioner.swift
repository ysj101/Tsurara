import AppKit
import TsuraraCore

/// length で画面外へ押し出された項目を、撮像中だけ表示可能な位置へ戻す。
@MainActor
final class AppKitMenuBarItemCapturePositioner: MenuBarItemCapturePositioning {
    private let sectionManager: SectionManager
    private let screenFrames: () -> [CGRect]
    private var ownedExpansionCount = 0

    init(
        sectionManager: SectionManager,
        screenFrames: (() -> [CGRect])? = nil
    ) {
        self.sectionManager = sectionManager
        self.screenFrames = screenFrames ?? { AppKitScreenGeometry.cgFrames }
    }

    func prepareForCapture(of windows: [MenuBarItemWindow]) -> Bool {
        guard windows.contains(where: { !isVisibleOnMenuBar($0) }) else { return false }
        guard sectionManager.beginCaptureExpansion() else { return false }
        ownedExpansionCount += 1
        return true
    }

    func isReadyForCapture(_ window: MenuBarItemWindow) -> Bool {
        isVisibleOnMenuBar(window)
    }

    func restoreAfterCapture() {
        guard ownedExpansionCount > 0 else { return }
        ownedExpansionCount -= 1
        sectionManager.endCaptureExpansion()
    }

    private func isVisibleOnMenuBar(_ window: MenuBarItemWindow) -> Bool {
        window.isVisibleOnMenuBar(displayFrames: screenFrames())
    }
}
