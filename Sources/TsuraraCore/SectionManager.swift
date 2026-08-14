import Foundation

@MainActor
public final class SectionManager {
    /// トグル項目の状態アイコン。非表示中は「つらら」を模した snowflake。
    /// トグルアイテムの状態アイコン（非表示中は「つらら」を模した snowflake）。
    public static let toggleCollapsedSymbolName = "snowflake"
    public static let toggleExpandedSymbolName = "circle.dotted"
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

    private static let toggleItemAccessibilityDescription = "Tsurara 非表示セクションの切り替え"
    private static let mainDividerAccessibilityDescription = "Tsurara 非表示セクションの境界"
    private static let subDividerAccessibilityDescription = "Tsurara 常時非表示セクションの境界"

    public let visibleSection: MenuBarSection
    public let hiddenSection: MenuBarSection
    public let alwaysHiddenSection: MenuBarSection
    public let toggleItem: any StatusItem

    /// 既存の length トグルに加えて、アプリ層へサブバー開閉要求を通知する。
    /// nil の場合は従来どおり非表示セクションのトグルだけを行う。
    public var onSubBarToggleRequested: (() -> Void)?

    /// 非表示セクションが畳まれているか。hiddenSection.isVisible を単一の情報源とする
    /// （二重管理にすると自動再非表示などの経路で不整合が起きるため）。
    public var isHiddenSectionCollapsed: Bool { !hiddenSection.isVisible }

    /// いずれかのメニューが開いている間 true。true の間に自動再非表示の時刻が来た場合は
    /// 保留し、false へ戻ったときに再スケジュールする（メニュー検知はアプリ層の責務）。
    public var isMenuTrackingActive = false {
        didSet {
            guard oldValue, !isMenuTrackingActive, isRehideDeferred else {
                return
            }
            isRehideDeferred = false
            scheduleRehideIfEnabled()
        }
    }

    // 展開時に復元する length。init 時点の値（AppKit では squareLength 番兵）を捕捉する。
    // 区切りの length を後から変える場合はこの値も更新すること。
    private let hiddenSectionExpandedLength: CGFloat
    private var alwaysHiddenSectionExpandedLength: CGFloat?
    private let settings: SettingsStore
    private let rehideTimer: any RehideTimerScheduling
    private var isRehideScheduled = false
    private var isRehideDeferred = false
    /// 撮像中は区切りを展開したままにし、トグルの最終状態だけをここへ合流する。
    private var captureDesiredCollapsedState: Bool?

    // サブ区切りの実行時の有効化/無効化で区切りを追加生成するために保持する。
    private let statusItemFactory: (String) -> any StatusItem

    public init(
        settings: SettingsStore,
        rehideTimer: any RehideTimerScheduling = FoundationRehideTimerScheduler(),
        statusItemFactory: @escaping (String) -> any StatusItem
    ) {
        self.settings = settings
        self.rehideTimer = rehideTimer
        self.statusItemFactory = statusItemFactory

        // 生成順が並び順を決める: NSStatusItem は後から作られたものほど左に並ぶため、
        // トグル → メイン区切り → サブ区切りの順に作ると
        // [常時非表示] ◆ [非表示] | [トグル] [表示]（時計側）の配置になる。
        // トグルは長さを変えないため、メイン区切りの拡大中も画面上に残る。
        let toggleItem = statusItemFactory(Self.toggleItemIdentifier)
        toggleItem.setIcon(
            symbolName: Self.toggleExpandedSymbolName,
            accessibilityDescription: Self.toggleItemAccessibilityDescription
        )
        self.toggleItem = toggleItem

        let mainDivider = statusItemFactory(Self.mainDividerIdentifier)
        mainDivider.setIcon(
            symbolName: Self.mainDividerSymbolName,
            accessibilityDescription: Self.mainDividerAccessibilityDescription
        )
        hiddenSectionExpandedLength = mainDivider.length

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

        // isVisible は「そのセクションのアイコンが画面上に見えているか」。
        visibleSection = MenuBarSection(
            kind: .visible,
            isVisible: true,
            dividerItem: nil
        )
        hiddenSection = MenuBarSection(
            kind: .hidden,
            isVisible: true,
            dividerItem: mainDivider
        )
        alwaysHiddenSection = MenuBarSection(
            kind: .alwaysHidden,
            isVisible: false,
            dividerItem: secondaryDivider
        )

        toggleItem.onClick = { [weak self] in
            self?.toggleHiddenSection()
        }
    }

    public func toggleHiddenSection() {
        if let desiredCollapsed = captureDesiredCollapsedState {
            captureDesiredCollapsedState = !desiredCollapsed
            return
        }
        if isHiddenSectionCollapsed {
            setHiddenSectionCollapsed(false)
            scheduleRehideIfEnabled()
        } else {
            cancelPendingRehide()
            setHiddenSectionCollapsed(true)
        }
        onSubBarToggleRequested?()
    }

    /// 画面外の項目を撮像する間だけ非表示セクションを強制展開する。
    /// 同じ length でも一度 collapse を経由させ、過密配置で自然に画面外へ
    /// 押し出された項目を WindowServer に再配置させる。
    @discardableResult
    public func beginCaptureExpansion() -> Bool {
        guard captureDesiredCollapsedState == nil,
              let dividerItem = hiddenSection.dividerItem
        else { return false }

        captureDesiredCollapsedState = isHiddenSectionCollapsed
        dividerItem.length = Self.hiddenSectionCollapsedLength
        dividerItem.length = hiddenSectionExpandedLength
        hiddenSection.isVisible = true
        toggleItem.setIcon(
            symbolName: Self.toggleExpandedSymbolName,
            accessibilityDescription: Self.toggleItemAccessibilityDescription
        )
        return true
    }

    /// 撮像開始時の状態と撮像中のトグル操作を合流した最終状態を反映する。
    public func endCaptureExpansion() {
        guard let desiredCollapsed = captureDesiredCollapsedState else { return }
        captureDesiredCollapsedState = nil
        setHiddenSectionCollapsed(desiredCollapsed)
        if desiredCollapsed {
            cancelPendingRehide()
        } else if !isRehideScheduled {
            scheduleRehideIfEnabled()
        }
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
    /// 非表示セクションが畳まれていると ◆ より左は表示できないため、併せて展開する。
    public func temporarilyShowAlwaysHiddenSection() {
        guard
            let dividerItem = alwaysHiddenSection.dividerItem,
            let expandedLength = alwaysHiddenSectionExpandedLength
        else { return }

        if isHiddenSectionCollapsed {
            setHiddenSectionCollapsed(false)
        }
        dividerItem.length = expandedLength
        alwaysHiddenSection.isVisible = true
    }

    public func rehideAlwaysHiddenSection() {
        guard let dividerItem = alwaysHiddenSection.dividerItem else {
            alwaysHiddenSection.isVisible = false
            return
        }

        dividerItem.length = Self.hiddenSectionCollapsedLength
        alwaysHiddenSection.isVisible = false
    }

    // MARK: - 自動再非表示

    /// 設定画面などで autoRehideEnabled が変更された際に呼ぶ。
    /// 展開中に有効化されたら直ちにスケジュールし、無効化されたら保留分も取り消す。
    public func autoRehideSettingDidChange() {
        if settings.autoRehideEnabled {
            if !isHiddenSectionCollapsed, !isRehideScheduled {
                scheduleRehideIfEnabled()
            }
        } else {
            cancelPendingRehide()
        }
    }

    private func scheduleRehideIfEnabled() {
        guard settings.autoRehideEnabled, !isHiddenSectionCollapsed else {
            return
        }

        isRehideScheduled = true
        rehideTimer.schedule(after: TimeInterval(settings.autoRehideSeconds)) {
            [weak self] in
            self?.rehideTimerFired()
        }
    }

    private func rehideTimerFired() {
        // 単発タイマーは発火時点で消費済み。メニュー追跡中なら deferred に移し、
        // 追跡終了時に改めて全秒数でスケジュールする（「タイマーを進めない」仕様の
        // 簡易実装として、残り時間の保持ではなく全秒数の再スケジュールを採る）。
        isRehideScheduled = false
        guard !isHiddenSectionCollapsed else { return }

        // スケジュール後に設定が無効化されたケースを発火時点で尊重する。
        guard settings.autoRehideEnabled else { return }

        if captureDesiredCollapsedState != nil {
            captureDesiredCollapsedState = true
            return
        }

        if isMenuTrackingActive {
            isRehideDeferred = true
            return
        }

        setHiddenSectionCollapsed(true)
    }

    private func cancelPendingRehide() {
        isRehideDeferred = false
        guard isRehideScheduled else { return }
        rehideTimer.cancel()
        isRehideScheduled = false
    }

    private func setHiddenSectionCollapsed(_ collapsed: Bool) {
        // 非表示セクションを畳むときは、一時表示中の常時非表示セクションも畳み直す
        // （◆ より左だけが残る状態は存在しないため）。
        if collapsed, alwaysHiddenSection.isVisible {
            rehideAlwaysHiddenSection()
        }
        hiddenSection.isVisible = !collapsed
        hiddenSection.dividerItem?.length = collapsed
            ? Self.hiddenSectionCollapsedLength
            : hiddenSectionExpandedLength
        toggleItem.setIcon(
            symbolName: collapsed
                ? Self.toggleCollapsedSymbolName
                : Self.toggleExpandedSymbolName,
            accessibilityDescription: Self.toggleItemAccessibilityDescription
        )
    }
}
