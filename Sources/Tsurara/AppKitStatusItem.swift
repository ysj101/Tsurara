import AppKit
import TsuraraCore

@MainActor
final class AppKitStatusItem: NSObject, StatusItem {
    /// アプリ層がメニュー設定など NSStatusItem 固有の操作を行うための参照。
    /// menu を設定すると onClick（target-action）は発火しなくなる点に注意。
    let underlying: NSStatusItem

    private var statusItem: NSStatusItem { underlying }

    var length: CGFloat {
        get { statusItem.length }
        set { statusItem.length = newValue }
    }

    var isVisible: Bool {
        get { statusItem.isVisible }
        set { statusItem.isVisible = newValue }
    }

    var onClick: (() -> Void)? {
        didSet {
            statusItem.button?.target = onClick == nil ? nil : self
            statusItem.button?.action = onClick == nil ? nil : #selector(handleClick)
        }
    }

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
    ) {
        self.underlying = statusItem
        super.init()
    }

    func setIcon(symbolName: String, accessibilityDescription: String) {
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
    }

    @objc private func handleClick() {
        onClick?()
    }
}
