import AppKit
import TsuraraCore

/// 非アクティブ・ボーダーレスのウィンドウに撮像済みアイコンを並べる AppKit 実装。
@MainActor
final class SubBarPanel: NSPanel, SubBarPanelPresenting {
    private enum Metrics {
        static let horizontalPadding: CGFloat = 6
        static let verticalPadding: CGFloat = 4
        static let cornerRadius: CGFloat = 8
        static let emptyWidth: CGFloat = 24
        static let emptyHeight: CGFloat = 22
    }

    var onDismissRequest: (() -> Void)?
    /// Issue #34 で実アイテムへのクリック転送を差し込むための境界。
    var onItemClick: ((ImagedMenuBarItem, MenuBarItemClickButton) -> Void)?

    private let layoutCalculator: any SubBarPanelLayoutCalculating
    private var anchorFrameProvider: (@MainActor () -> CGRect?)?
    // AppKit の monitor token は Sendable ではない。登録・解除は MainActor 上だけで
    // 行い、nonisolated deinit から最終解除するため token の格納だけ unsafe とする。
    nonisolated(unsafe) private var localClickMonitor: Any?
    nonisolated(unsafe) private var globalClickMonitor: Any?

    init(
        layoutCalculator: any SubBarPanelLayoutCalculating =
            SubBarPanelLayoutCalculator()
    ) {
        self.layoutCalculator = layoutCalculator
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func present(
        items: [ImagedMenuBarItem],
        anchorFrame: @escaping @MainActor () -> CGRect?
    ) -> Bool {
        guard let currentAnchorFrame = anchorFrame() else { return false }
        // MenuBarItemImager が order 順に生成するため、ここでの再ソートは不要。
        let itemWidth = items.reduce(CGFloat.zero) {
            $0 + max(1, $1.frame.width)
        }
        let itemHeight = items.map { max(1, $0.frame.height) }.max()
            ?? Metrics.emptyHeight
        let desiredSize = CGSize(
            width: max(Metrics.emptyWidth, itemWidth) + Metrics.horizontalPadding * 2,
            height: itemHeight + Metrics.verticalPadding * 2
        )
        let screens = NSScreen.screens.map {
            SubBarScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        guard let panelFrame = layoutCalculator.panelFrame(
            anchorFrame: currentAnchorFrame,
            desiredSize: desiredSize,
            screens: screens
        ) else { return false }

        anchorFrameProvider = anchorFrame
        setFrame(panelFrame, display: false)
        contentView = makeContentView(
            items: items,
            contentWidth: itemWidth,
            itemHeight: itemHeight,
            panelSize: panelFrame.size
        )
        installOutsideClickMonitors()
        orderFrontRegardless()
        return true
    }

    func dismiss() {
        removeOutsideClickMonitors()
        anchorFrameProvider = nil
        orderOut(nil)
    }

    private func makeContentView(
        items: [ImagedMenuBarItem],
        contentWidth: CGFloat,
        itemHeight: CGFloat,
        panelSize: CGSize
    ) -> NSView {
        let root = NSVisualEffectView(frame: CGRect(origin: .zero, size: panelSize))
        root.material = .menu
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = Metrics.cornerRadius
        root.layer?.masksToBounds = true

        let availableWidth = max(0, panelSize.width - Metrics.horizontalPadding * 2)
        let scrollView = NSScrollView(
            frame: CGRect(
                x: Metrics.horizontalPadding,
                y: Metrics.verticalPadding,
                width: availableWidth,
                height: itemHeight
            )
        )
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = contentWidth > availableWidth
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let document = NSView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: max(contentWidth, availableWidth),
                height: itemHeight
            )
        )
        var x = CGFloat.zero
        for item in items {
            let size = CGSize(width: max(1, item.frame.width), height: max(1, item.frame.height))
            let itemView = SubBarItemView(
                frame: CGRect(x: x, y: (itemHeight - size.height) / 2, width: size.width, height: size.height)
            )
            itemView.image = NSImage(cgImage: item.image, size: size)
            itemView.toolTip = item.owner.name
            itemView.onClick = { [weak self] button in
                self?.onItemClick?(item, button)
            }
            document.addSubview(itemView)
            x += size.width
        }
        scrollView.documentView = document
        root.addSubview(scrollView)
        return root
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) {
            [weak self] event in
            MainActor.assumeIsolated {
                self?.dismissIfClickIsOutside(event)
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) {
            [weak self] event in
            MainActor.assumeIsolated {
                self?.dismissIfClickIsOutside(event)
            }
        }
    }

    private func dismissIfClickIsOutside(_ event: NSEvent) {
        let location: CGPoint
        if let eventWindow = event.window {
            location = eventWindow.convertToScreen(
                CGRect(origin: event.locationInWindow, size: .zero)
            ).origin
        } else {
            // グローバルモニタの window=nil イベントは locationInWindow 自体が
            // AppKit の screen 座標。イベント発生時の座標を同期的に使用する。
            location = event.locationInWindow
        }
        let currentAnchorFrame = anchorFrameProvider?()
        // アンカー上のクリックは StatusItem の action に任せる。先に外側クリックとして
        // close すると、同じイベントの toggle が再び open してしまうため。
        guard !frame.contains(location),
              currentAnchorFrame?.contains(location) != true
        else { return }
        onDismissRequest?()
    }

    private func removeOutsideClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    deinit {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
    }
}

/// クリック転送を後から追加できる、画像表示専用のセル。
@MainActor
private final class SubBarItemView: NSImageView {
    var onClick: ((MenuBarItemClickButton) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageAlignment = .alignCenter
        imageScaling = .scaleProportionallyUpOrDown
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseUp(with event: NSEvent) {
        onClick?(event.modifierFlags.contains(.control) ? .right : .left)
    }

    override func rightMouseUp(with event: NSEvent) {
        onClick?(.right)
    }
}
