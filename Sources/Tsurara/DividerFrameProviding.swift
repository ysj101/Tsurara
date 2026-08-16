import CoreGraphics

/// WindowServer の ID に依存せず、区切りの画面上の位置を撮像経路へ渡す境界。
@MainActor
protocol DividerFrameProviding: AnyObject {
    /// CGWindow と同じ、主画面左上原点のグローバル座標。
    var dividerFrame: CGRect? { get }
}
