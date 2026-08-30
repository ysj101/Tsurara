import CoreGraphics

public enum MenuBarItemWindowCandidate {
    // 無関係なウィンドウの誤検出を避けるための保守的な上限。
    // 512pt を超える幅広項目を扱えない点は、既知の課題として残す。
    private static let maxItemWidth: CGFloat = 512
    // メニューバー項目はディスプレイ上端にアンカーされる。HUD 等を除外するための許容ずれ。
    private static let topAnchorTolerance: CGFloat = 16

    public static func isCandidateLevel(layer: Int32, statusWindowLevel: Int32) -> Bool {
        let levelOffset = Int64(layer) - Int64(statusWindowLevel)
        // CGWindowMenuBarItemInterfaceTracker は status 未満をクリックで開いた UI と分類し、
        // CoreGraphicsMenuBarItemMover は候補を Cmd ドラッグ可能な status item と仮定するため、
        // mainMenu レベルを混在させない。
        return (0 ... 2).contains(levelOffset)
    }

    public static func isMenuBarItemWindow(
        layer: Int32,
        frame: CGRect,
        statusWindowLevel: Int32,
        displayFrames: [CGRect]
    ) -> Bool {
        // status レベルを早期受理する場合も、実体のない 0 サイズを列挙しないため先に検証する。
        guard frame.width > 0, frame.height > 0 else { return false }

        guard isCandidateLevel(layer: layer, statusWindowLevel: statusWindowLevel) else {
            return false
        }

        // status レベルの画面外項目も撮像するため、幾何条件より先に従来どおり受理する。
        guard layer != statusWindowLevel else { return true }

        guard frame.width <= maxItemWidth else { return false }

        // HUD や縦積み画面の別端を拾わず、実際の上端にアンカーされた項目だけに絞る。
        // 高さ上限は maxY の帯内条件が兼ねる。
        // 隠し項目は負の x 座標にあり得るため、水平方向の交差は要求しない。
        return displayFrames.contains { display in
            frame.minY >= display.minY
                && frame.minY <= display.minY + topAnchorTolerance
                && frame.maxY <= display.minY + MenuBarItemWindow.menuBarBandHeight
        }
    }
}
