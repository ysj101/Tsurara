import CoreGraphics

/// AppKit の左下原点座標を CGWindow の主画面左上原点座標へ変換する。
public enum CGWindowCoordinateSpace {
    public static func frame(
        fromAppKit frame: CGRect,
        primaryMaxY: CGFloat
    ) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    /// CGWindow の主画面左上原点座標を AppKit の左下原点座標へ変換する。
    public static func frame(
        toAppKit frame: CGRect,
        primaryMaxY: CGFloat
    ) -> CGRect {
        // y 反転は対合なので、AppKit からの変換と同じ式で元へ戻せる。
        self.frame(fromAppKit: frame, primaryMaxY: primaryMaxY)
    }
}
