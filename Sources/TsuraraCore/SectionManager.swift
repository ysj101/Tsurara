import Foundation

@MainActor
public final class SectionManager {
    /// メイン区切り（◇）のアイコン。非表示中は「つらら」を模した snowflake。
    public static let mainDividerCollapsedSymbolName = "snowflake"
    public static let mainDividerExpandedSymbolName = "circle.dotted"
    public static let subDividerSymbolName = "diamond"

    /// NSStatusItem の autosaveName に使う識別子。位置の永続化キーを固定し、
    /// 再起動やサブ区切りの有効化/無効化で並びが入れ替わらないようにする。
    public static let mainDividerIdentifier = "Tsurara.mainDivider"
    public static let subDividerIdentifier = "Tsurara.subDivider"

    /// セクションを畳む際に、区切りの左側を画面外へ押し出す長さ。
    /// 実機での適切な値の調整は #6 で行う。
    public static let hiddenSectionCollapsedLength: CGFloat = 10_000

    private static let mainDividerAccessibilityDescription = "Tsurara 非表示セクションの切り替え"
    private static let subDividerAccessibilityDescription = "Tsurara 常時非表示セクションの境界"

    public let visibleSection: MenuBarSection
    public let hiddenSection: MenuBarSection
    public let alwaysHiddenSection: MenuBarSection

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
        // メイン区切り（◇）→ サブ区切り（◆）の順に作ると
        // [常時非表示] ◆ [非表示] ◇ [表示]（時計側）の配置になる。
        let mainDivider = statusItemFactory(Self.mainDividerIdentifier)
        mainDivider.setIcon(
            symbolName: Self.mainDividerExpandedSymbolName,
            accessibilityDescription: Self.mainDividerAccessibilityDescription
        )
        hiddenSectionExpandedLength = mainDivider.length

        let secondaryDivider: (any StatusItem)?
        if settings.alwaysHiddenSectionEnabled {
            let item = statusItemFactory(Self.subDividerIdentifier)
            item.setIcon(
                symbolName: Self.subDividerSymbolName,
                accessibilityDescription: Self.subDividerAccessibilityDescription
            )
            // 常時非表示セクションは起動時から length 拡大で collapse しておく。
            alwaysHiddenSectionExpandedLength = item.length
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

        mainDivider.onClick = { [weak self] in
            self?.toggleHiddenSection()
        }
    }

    public func toggleHiddenSection() {
        if isHiddenSectionCollapsed {
            setHiddenSectionCollapsed(false)
            scheduleRehideIfEnabled()
        } else {
            cancelPendingRehide()
            setHiddenSectionCollapsed(true)
        }
    }

    // MARK: - 常時非表示セクション

    public func setAlwaysHiddenSectionEnabled(_ enabled: Bool) {
        settings.alwaysHiddenSectionEnabled = enabled

        if enabled {
            if alwaysHiddenSection.dividerItem == nil {
                let item = statusItemFactory(Self.subDividerIdentifier)
                item.setIcon(
                    symbolName: Self.subDividerSymbolName,
                    accessibilityDescription: Self.subDividerAccessibilityDescription
                )
                alwaysHiddenSectionExpandedLength = item.length
                alwaysHiddenSection.dividerItem = item
            }
            rehideAlwaysHiddenSection()
        } else {
            alwaysHiddenSection.dividerItem?.isVisible = false
            alwaysHiddenSection.dividerItem = nil
            alwaysHiddenSectionExpandedLength = nil
            alwaysHiddenSection.isVisible = false
        }
    }

    /// 設定画面の「常時非表示セクションを一時的に表示する」ボタン用（接続は #11）。
    public func temporarilyShowAlwaysHiddenSection() {
        guard
            let dividerItem = alwaysHiddenSection.dividerItem,
            let expandedLength = alwaysHiddenSectionExpandedLength
        else { return }

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
        hiddenSection.isVisible = !collapsed
        hiddenSection.dividerItem?.length = collapsed
            ? Self.hiddenSectionCollapsedLength
            : hiddenSectionExpandedLength
        hiddenSection.dividerItem?.setIcon(
            symbolName: collapsed
                ? Self.mainDividerCollapsedSymbolName
                : Self.mainDividerExpandedSymbolName,
            accessibilityDescription: Self.mainDividerAccessibilityDescription
        )
    }
}
