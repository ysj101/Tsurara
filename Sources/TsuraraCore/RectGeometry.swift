import CoreGraphics

public extension CGRect {
    /// 交差部分の面積。交差しなければ 0。
    /// 「最も広く重なる画面」を選ぶ判定で、配置計算と撮像マスクの双方が使う。
    func intersectionArea(with other: CGRect) -> CGFloat {
        let overlap = intersection(other)
        guard !overlap.isNull else { return 0 }
        return overlap.width * overlap.height
    }
}
