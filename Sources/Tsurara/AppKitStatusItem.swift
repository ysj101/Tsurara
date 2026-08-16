import AppKit
import TsuraraCore

@MainActor
final class AppKitStatusItem: NSObject, StatusItem, DividerFrameProviding {
    /// アプリ層がメニュー設定など NSStatusItem 固有の操作を行うための参照。
    let underlying: NSStatusItem

    private var statusItem: NSStatusItem { underlying }

    /// CGWindow と同じ、主画面左上原点のグローバル座標。
    var dividerFrame: CGRect? {
        guard let button = statusItem.button, let window = button.window,
              let primaryMaxY = NSScreen.screens.first?.frame.maxY
        else { return nil }
        let appKitFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return CGWindowCoordinateSpace.frame(
            fromAppKit: appKitFrame,
            primaryMaxY: primaryMaxY
        )
    }

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

    func remove() {
        NSStatusBar.system.removeStatusItem(underlying)
    }

    @objc private func handleClick() {
        // 右クリックと Control+左クリック（macOS の副ボタン規約）を副操作として扱い、
        // それ以外（キーボードや VoiceOver の press を含む）はすべて主操作に流す。
        let event = NSApp.currentEvent
        let isSecondaryClick =
            event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp
                && event?.modifierFlags.contains(.control) == true)
        if isSecondaryClick {
            onRightClick?()
        } else {
            onClick?()
        }
    }

    private func updateClickHandling() {
        let handlesClicks = onClick != nil || onRightClick != nil
        statusItem.button?.target = handlesClicks ? self : nil
        statusItem.button?.action = handlesClicks ? #selector(handleClick) : nil
    }
}
