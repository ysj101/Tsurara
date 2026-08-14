import CoreGraphics
import Foundation
import TsuraraCore

final class MockStatusItem: StatusItem {
    struct Icon: Equatable {
        let symbolName: String
        let accessibilityDescription: String
    }

    var windowID: CGWindowID?

    var length: CGFloat {
        didSet { lengthHistory.append(length) }
    }

    var isVisible: Bool {
        didSet { isVisibleHistory.append(isVisible) }
    }

    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    private(set) var lengthHistory: [CGFloat] = []
    private(set) var isVisibleHistory: [Bool] = []
    private(set) var icons: [Icon] = []

    var iconSymbolNames: [String] { icons.map(\.symbolName) }

    init(
        windowID: CGWindowID? = nil,
        length: CGFloat = 0,
        isVisible: Bool = true
    ) {
        self.windowID = windowID
        self.length = length
        self.isVisible = isVisible
    }

    func setIcon(symbolName: String, accessibilityDescription: String) {
        icons.append(Icon(symbolName: symbolName, accessibilityDescription: accessibilityDescription))
    }

    private(set) var isRemoved = false

    func remove() {
        isRemoved = true
    }

    func fireClick() {
        onClick?()
    }
}
