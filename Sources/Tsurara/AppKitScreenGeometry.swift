import AppKit
import TsuraraCore

/// NSScreen の実画面一覧を CGWindow と同じグローバル座標で提供する。
@MainActor
enum AppKitScreenGeometry {
    static var cgFrames: [CGRect] {
        let screens = NSScreen.screens
        guard let primaryMaxY = screens.first?.frame.maxY else { return [] }
        return screens.map {
            CGWindowCoordinateSpace.frame(
                fromAppKit: $0.frame,
                primaryMaxY: primaryMaxY
            )
        }
    }
}
