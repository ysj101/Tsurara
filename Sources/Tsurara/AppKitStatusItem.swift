import AppKit
import TsuraraCore

@MainActor
final class AppKitStatusItem: NSObject, StatusItem {
    /// アプリ層がメニュー設定など NSStatusItem 固有の操作を行うための参照。
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
        didSet { updateClickHandling() }
    }

    var onRightClick: (() -> Void)? {
        didSet { updateClickHandling() }
    }

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        ),
        autosaveName: String? = nil
    ) {
        self.underlying = statusItem
        super.init()
        // 位置の永続化キーを固定し、再起動や項目数の変化で並びが崩れないようにする。
        if let autosaveName {
            statusItem.autosaveName = autosaveName
        }
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func setIcon(symbolName: String, accessibilityDescription: String) {
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
    }

    @objc private func handleClick() {
        switch NSApp.currentEvent?.type {
        case .rightMouseUp:
            onRightClick?()
        case .leftMouseUp, .none:
            onClick?()
        default:
            break
        }
    }

    private func updateClickHandling() {
        let handlesClicks = onClick != nil || onRightClick != nil
        statusItem.button?.target = handlesClicks ? self : nil
        statusItem.button?.action = handlesClicks ? #selector(handleClick) : nil
    }
}
