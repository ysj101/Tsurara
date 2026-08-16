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
}
