import Foundation

@MainActor
public protocol StatusItem: AnyObject {
    var length: CGFloat { get set }
    var isVisible: Bool { get set }
    var onClick: (() -> Void)? { get set }

    func setIcon(symbolName: String, accessibilityDescription: String)
}
