import Foundation
import TsuraraCore

final class MockStatusItem: StatusItem {
    var length: CGFloat {
        didSet { lengthHistory.append(length) }
    }

    var isVisible: Bool
    var onClick: (() -> Void)?

    private(set) var lengthHistory: [CGFloat] = []
    private(set) var iconSymbolNames: [String] = []

    init(length: CGFloat = 0, isVisible: Bool = true) {
        self.length = length
        self.isVisible = isVisible
    }

    func setIcon(symbolName: String, accessibilityDescription: String) {
        iconSymbolNames.append(symbolName)
    }

    func fireClick() {
        onClick?()
    }
}
