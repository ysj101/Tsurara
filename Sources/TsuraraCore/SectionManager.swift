import Foundation

@MainActor
public final class SectionManager {
    /// トグル項目の状態アイコン。閉時は「つらら」を模した snowflake。
    public static let toggleClosedSymbolName = "snowflake"
    public static let toggleOpenSymbolName = "circle.dotted"
    /// メイン区切り（伸びるセパレータ）の固定アイコン。
    public static let mainDividerSymbolName = "poweron"
    public static let subDividerSymbolName = "diamond"

    /// NSStatusItem の autosaveName に使う識別子。位置の永続化キーを固定し、
    /// 再起動やサブ区切りの有効化/無効化で並びが入れ替わらないようにする。
    public static let toggleItemIdentifier = "Tsurara.toggleItem"
    public static let mainDividerIdentifier = "Tsurara.mainDivider"
    public static let subDividerIdentifier = "Tsurara.subDivider"

    /// セクションを畳む際に、区切りの左側を画面外へ押し出す長さ。
    /// 実機での適切な値の調整は #6 で行う。
    public static let hiddenSectionCollapsedLength: CGFloat = 10_000

    private static let toggleItemAccessibilityDescription = "Tsurara サブバーの切り替え"
    private static let mainDividerAccessibilityDescription = "Tsurara 非表示セクションの境界"
    private static let subDividerAccessibilityDescription = "Tsurara 常時非表示セクションの境界"

    public let visibleSection: MenuBarSection
    public let hiddenSection: MenuBarSection
    public let alwaysHiddenSection: MenuBarSection
    public let toggleItem: any StatusItem

    /// アプリ層へサブバー開閉要求を通知する。
    public var onSubBarToggleRequested: (() -> Void)?
    /// アプリ層へサブバーを閉じる冪等な要求を通知する。
    public var onSubBarCloseRequested: (() -> Void)?

    /// 実際にサブバーが表示されているか。撮像中はまだ false のままとする。
    public private(set) var isSubBarOpen = false

    /// いずれかのメニュー／ポップオーバーが開いている間 true。
    /// true になった時点で自動クローズを一時停止し、false で残り時間から再開する。
    /// メニュー検知はアプリ層の責務とする。
    public var isMenuTrackingActive = false {
        didSet {
            guard oldValue != isMenuTrackingActive, isSubBarOpen else { return }
            if isMenuTrackingActive {
                pausePendingRehide()
            } else {
                resumePendingRehide()
            }
        }
    }

    // 常時非表示セクションの一時表示時だけ復元する length。
    // init 時点の値（AppKit では squareLength 番兵）を捕捉する。
    private let hiddenSectionTemporaryDisplayLength: CGFloat
    private var alwaysHiddenSectionExpandedLength: CGFloat?
    private let settings: SettingsStore
    private let rehideTimer: any RehideTimerScheduling
    private let currentTime: @MainActor () -> TimeInterval
    private var isRehideScheduled = false
    private var isRehideDeferred = false
    /// 撮像とクリック転送が同じ一時展開を共有できるよう、所有者数を保持する。
    private var captureExpansionDepth = 0
    private var rehideDeadline: TimeInterval?
    private var remainingRehideInterval: TimeInterval?

    // サブ区切りの実行時の有効化/無効化で区切りを追加生成するために保持する。
    private let statusItemFactory: (String) -> any StatusItem

    public init(
        settings: SettingsStore,
        rehideTimer: any RehideTimerScheduling = FoundationRehideTimerScheduler(),
        currentTime: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        statusItemFactory: @escaping (String) -> any StatusItem
    ) {
        self.settings = settings
        self.rehideTimer = rehideTimer
        self.currentTime = currentTime
        self.statusItemFactory = statusItemFactory

        // 生成順が並び順を決める: NSStatusItem は後から作られたものほど左に並ぶため、
        // トグル → メイン区切り → サブ区切りの順に作ると
        // [常時非表示] ◆ [非表示] | [トグル] [表示]（時計側）の配置になる。
        // トグルは長さを変えないため、メイン区切りの拡大中も画面上に残る。
        let toggleItem = statusItemFactory(Self.toggleItemIdentifier)
        toggleItem.setIcon(
            symbolName: Self.toggleClosedSymbolName,
            accessibilityDescription: Self.toggleItemAccessibilityDescription
        )
        self.toggleItem = toggleItem

        let mainDivider = statusItemFactory(Self.mainDividerIdentifier)
        mainDivider.setIcon(
            symbolName: Self.mainDividerSymbolName,
            accessibilityDescription: Self.mainDividerAccessibilityDescription
        )
        hiddenSectionTemporaryDisplayLength = mainDivider.length
        // 非表示アイコンはサブバーから利用するため、メニューバー内では常に隠す。
        mainDivider.length = Self.hiddenSectionCollapsedLength

        let secondaryDivider: (any StatusItem)?
        if settings.alwaysHiddenSectionEnabled {
            let item = Self.makeSubDivider(statusItemFactory)
            alwaysHiddenSectionExpandedLength = item.length
            // 常時非表示セクションは起動時から length 拡大で collapse しておく。
            item.length = Self.hiddenSectionCollapsedLength
            secondaryDivider = item
        } else {
            alwaysHiddenSectionExpandedLength = nil
            secondaryDivider = nil
        }

        visibleSection = MenuBarSection(
            kind: .visible,
            isVisible: true,
            dividerItem: nil
        )
        hiddenSection = MenuBarSection(
            kind: .hidden,
            isVisible: false,
            dividerItem: mainDivider
        )
        alwaysHiddenSection = MenuBarSection(
            kind: .alwaysHidden,
            isVisible: false,
            dividerItem: secondaryDivider
        )

        toggleItem.onClick = { [weak self] in
            self?.toggleSubBar()
        }
    }

    public func toggleSubBar() {
        if alwaysHiddenSection.isVisible {
            rehideAlwaysHiddenSection()
        }
        onSubBarToggleRequested?()
    }

    /// アプリ層での実際の開閉結果を反映し、状態アイコンと自動クローズを同期する。
    public func setSubBarOpen(_ open: Bool) {
        guard isSubBarOpen != open else { return }
        isSubBarOpen = open
        toggleItem.setIcon(
            symbolName: open ? Self.toggleOpenSymbolName : Self.toggleClosedSymbolName,
            accessibilityDescription: Self.toggleItemAccessibilityDescription
        )
        if open {
            scheduleRehideIfEnabled()
        } else {
            cancelPendingRehide()
        }
    }

    /// 画面外の項目を撮像する間だけ非表示セクションを強制展開する。
    /// 同じ length でも一度 collapse を経由させ、過密配置で自然に画面外へ
    /// 押し出された項目を WindowServer に再配置させる。
    @discardableResult
    public func beginCaptureExpansion() -> Bool {
        guard let dividerItem = hiddenSection.dividerItem else { return false }

        if captureExpansionDepth > 0 {
            captureExpansionDepth += 1
            return true
        }

        captureExpansionDepth = 1
        dividerItem.length = Self.hiddenSectionCollapsedLength
        dividerItem.length = hiddenSectionTemporaryDisplayLength
        hiddenSection.isVisible = true
        return true
    }

    /// 最後の撮像所有者が終了したら、非表示セクションを再び画面外へ戻す。
    public func endCaptureExpansion() {
        guard captureExpansionDepth > 0 else { return }
        captureExpansionDepth -= 1
        guard captureExpansionDepth == 0 else { return }
        hiddenSection.dividerItem?.length = Self.hiddenSectionCollapsedLength
        hiddenSection.isVisible = false
    }

    // MARK: - 常時非表示セクション

    public func setAlwaysHiddenSectionEnabled(_ enabled: Bool) {
        if enabled {
            if alwaysHiddenSection.dividerItem == nil {
                // 注意: 実行時生成では autosaveName の保存位置が復元されるため、
                // 「生成順 = 並び順」の契約は初回起動時のみ成立する。ユーザーが
                // ◆ を ◇ より右へ動かした場合の並びは Cmd ドラッグでの再配置に委ねる。
                let item = Self.makeSubDivider(statusItemFactory)
                alwaysHiddenSectionExpandedLength = item.length
                alwaysHiddenSection.dividerItem = item
            }
            rehideAlwaysHiddenSection()
        } else {
            if alwaysHiddenSection.isVisible {
                rehideAlwaysHiddenSection()
            }
            // isVisible=false は autosaveName に永続化され次回生成時も不可視になる。
            // 必ず remove() でステータスバーから取り除く（リークと永続化の両方を防ぐ）。
            alwaysHiddenSection.dividerItem?.remove()
            alwaysHiddenSection.dividerItem = nil
            alwaysHiddenSectionExpandedLength = nil
            alwaysHiddenSection.isVisible = false
        }
        // 生成・破棄が完了してから永続化し、途中失敗で設定と実態が食い違わないようにする。
        settings.alwaysHiddenSectionEnabled = enabled
    }

    private static func makeSubDivider(
        _ factory: (String) -> any StatusItem
    ) -> any StatusItem {
        let item = factory(Self.subDividerIdentifier)
        item.setIcon(
            symbolName: Self.subDividerSymbolName,
            accessibilityDescription: Self.subDividerAccessibilityDescription
        )
        // 過去セッションで isVisible=false が autosave 経由で残っていても表示させる。
        item.isVisible = true
        return item
    }

    /// 設定画面の「常時非表示セクションを一時的に表示する」ボタン用（接続は #11）。
    /// ◆ より左を表示できるよう、この経路に限ってメイン区切りも一時的に復元する。
    public func temporarilyShowAlwaysHiddenSection() {
        guard
            let dividerItem = alwaysHiddenSection.dividerItem,
            let expandedLength = alwaysHiddenSectionExpandedLength
        else { return }

        if isSubBarOpen {
            onSubBarCloseRequested?()
        }
        hiddenSection.dividerItem?.length = hiddenSectionTemporaryDisplayLength
        hiddenSection.isVisible = true
        dividerItem.length = expandedLength
        alwaysHiddenSection.isVisible = true
    }

    public func rehideAlwaysHiddenSection() {
        let wasTemporarilyShown = alwaysHiddenSection.isVisible
        guard let dividerItem = alwaysHiddenSection.dividerItem else {
            alwaysHiddenSection.isVisible = false
            return
        }

        dividerItem.length = Self.hiddenSectionCollapsedLength
        alwaysHiddenSection.isVisible = false
        if wasTemporarilyShown {
            hiddenSection.dividerItem?.length = Self.hiddenSectionCollapsedLength
            hiddenSection.isVisible = false
        }
    }

    // MARK: - サブバーの自動クローズ

    /// 設定画面などで自動クローズ設定が変更された際に呼ぶ。
    /// サブバー表示中の有効化・秒数変更は、新しい全秒数でスケジュールし直す。
    public func autoRehideSettingDidChange() {
        if settings.autoRehideEnabled {
            if isSubBarOpen {
                cancelPendingRehide()
                scheduleRehideIfEnabled()
            }
        } else {
            cancelPendingRehide()
        }
    }

    private func scheduleRehideIfEnabled(after interval: TimeInterval? = nil) {
        guard settings.autoRehideEnabled, isSubBarOpen else {
            return
        }

        let delay = interval ?? TimeInterval(settings.autoRehideSeconds)
        if isMenuTrackingActive {
            isRehideDeferred = true
            remainingRehideInterval = delay
            return
        }

        isRehideDeferred = false
        remainingRehideInterval = nil
        isRehideScheduled = true
        rehideDeadline = currentTime() + delay
        rehideTimer.schedule(after: delay) {
            [weak self] in
            self?.rehideTimerFired()
        }
    }

    private func rehideTimerFired() {
        // 単発タイマーは発火時点で消費済み。通常はメニュー開始時にキャンセル
        // されるが、発火との競合時にも追跡中のクローズを避ける。
        isRehideScheduled = false
        rehideDeadline = nil
        guard isSubBarOpen else { return }

        // スケジュール後に設定が無効化されたケースを発火時点で尊重する。
        guard settings.autoRehideEnabled else { return }

        if isMenuTrackingActive {
            isRehideDeferred = true
            remainingRehideInterval = 0
            return
        }

        onSubBarCloseRequested?()
    }

    private func pausePendingRehide() {
        guard settings.autoRehideEnabled else { return }

        if isRehideScheduled {
            let deadline = rehideDeadline ?? currentTime()
            remainingRehideInterval = max(0, deadline - currentTime())
            rehideTimer.cancel()
            isRehideScheduled = false
            rehideDeadline = nil
        } else if remainingRehideInterval == nil {
            remainingRehideInterval = TimeInterval(settings.autoRehideSeconds)
        }
        isRehideDeferred = true
    }

    private func resumePendingRehide() {
        guard isRehideDeferred else { return }
        let remaining = remainingRehideInterval
        isRehideDeferred = false
        remainingRehideInterval = nil
        scheduleRehideIfEnabled(after: remaining)
    }

    private func cancelPendingRehide() {
        isRehideDeferred = false
        remainingRehideInterval = nil
        rehideDeadline = nil
        if isRehideScheduled {
            rehideTimer.cancel()
            isRehideScheduled = false
        }
    }
}
