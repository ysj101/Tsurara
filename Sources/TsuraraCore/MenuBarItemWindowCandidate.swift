import CoreGraphics

public enum MenuBarItemWindowCandidate {
    public static func isMenuBarItemWindow(
        layer: Int32,
        frame: CGRect,
        statusWindowLevel: Int32,
        displayFrames: [CGRect]
    ) -> Bool {
        // status レベルの画面外項目も撮像するため、幾何条件より先に従来どおり受理する。
        guard layer != statusWindowLevel else { return true }

        let levelOffset = Int64(layer) - Int64(statusWindowLevel)
        // mainMenu から status の直上 2 段までは実装差を許容しつつ、
        // より上層のポップアップメニューを候補に含めないため範囲を狭く保つ。
        guard (-1 ... 2).contains(levelOffset) else { return false }

        // 64pt は既存の表示判定と揃え、長いテキスト項目には余裕を持たせつつ、
        // 画面幅のメニューバー本体や大きなパネルを除外する。
        guard
            frame.width > 0,
            frame.height > 0,
            frame.width <= 512,
            frame.height <= 64
        else { return false }

        // 隠し項目は負の x 座標にあり得るため、水平方向の交差は要求しない。
        let menuBarDisplays = displayFrames.filter { display in
            frame.maxY > display.minY && frame.minY < display.minY + 64
        }
        guard !menuBarDisplays.isEmpty else { return false }

        // 同じ高さに並ぶ画面があっても、そのどれかのメニューバー本体を
        // 別画面の項目と誤認しないよう、該当する全画面より狭いことを求める。
        return menuBarDisplays.allSatisfy { frame.width < $0.width }
    }
}
