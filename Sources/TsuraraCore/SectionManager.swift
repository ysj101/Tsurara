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

    /// 非表示セクションを畳む際に、区切りの左側を画面外へ押し出す長さ。
    /// 実機での適切な値の調整は #6 で行う。
    public static let hiddenSectionCollapsedLength: CGFloat = 10_000

    private static let mainDividerAccessibilityDescription = "Tsurara 非表示セクションの切り替え"

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
    private let settings: SettingsStore
    private let rehideTimer: any RehideTimerScheduling
    private var isRehideScheduled = false
    private var isRehideDeferred = false

    // サブ区切りの実行時の有効化/無効化（#9）で区切りを追加生成するために保持する。
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
                accessibilityDescription: "Tsurara 常時非表示セクションの境界"
            )
            secondaryDivider = item
        } else {
            secondaryDivider = nil
        }

        // isVisible は「そのセクションのアイコンが画面上に見えているか」。
        // length 拡大による collapse は toggleHiddenSection()（#5）/#9 で遷移する。
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
            isVisible: true,
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
        // 追跡終了時に改めて全秒数でスケジュールする。
        isRehideScheduled = false
        guard !isHiddenSectionCollapsed else { return }

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
