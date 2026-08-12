import Foundation

/// NSStatusItem の length に渡す AppKit の番兵値（NSStatusItem.variableLength /
/// .squareLength と同値）。ロジック層が AppKit を import せずに指定できるようにする。
public enum StatusItemLength {
    public static let variable: CGFloat = -1
    public static let square: CGFloat = -2
}

@MainActor
public protocol StatusItem: AnyObject {
    var length: CGFloat { get set }
    var isVisible: Bool { get set }
    /// クリック時に呼ばれる。実装がメニューを併設している場合は発火しないことがある
    /// （NSStatusItem は menu 設定時に target-action を送らない）。
    var onClick: (() -> Void)? { get set }

    /// 副操作（右クリック / Control+左クリック）時に呼ばれる。
    var onRightClick: (() -> Void)? { get set }

    func setIcon(symbolName: String, accessibilityDescription: String)
}
