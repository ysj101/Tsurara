import AppKit
import TsuraraCore

@MainActor
final class AppKitStatusItem: NSObject, StatusItem {
    /// アプリ層がメニュー設定など NSStatusItem 固有の操作を行うための参照。
    let underlying: NSStatusItem

    private var statusItem: NSStatusItem { underlying }

    /// CGWindowList / ScreenCaptureKit で同じ NSStatusItem ウィンドウを解決する ID。
    /// macOS 26 系ではステータス項目の `windowNumber` が UInt32 を超える値
    /// （実測 2^32）を返すため、`CGWindowID(_:)` の非失敗変換はトラップする。
    /// 収まらない場合は nil を返し、呼び出し側は撮像を諦めてサブバーを閉じる。
    var windowID: CGWindowID? {
        guard let number = statusItem.button?.window?.windowNumber, number > 0 else {
            return nil
        }
        return CGWindowID(exactly: number)
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
