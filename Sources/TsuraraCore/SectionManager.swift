@MainActor
public final class SectionManager {
    /// メイン区切り（◇）のアイコン。非表示中は「つらら」を模した snowflake。
    /// 表示中アイコンへの切り替えは #7 で実装する。
    public static let mainDividerCollapsedSymbolName = "snowflake"
    public static let subDividerSymbolName = "diamond"

    /// NSStatusItem の autosaveName に使う識別子。位置の永続化キーを固定し、
    /// 再起動やサブ区切りの有効化/無効化で並びが入れ替わらないようにする。
    public static let mainDividerIdentifier = "Tsurara.mainDivider"
    public static let subDividerIdentifier = "Tsurara.subDivider"

    public let visibleSection: MenuBarSection
    public let hiddenSection: MenuBarSection
    public let alwaysHiddenSection: MenuBarSection

    // サブ区切りの実行時の有効化/無効化（#9）で区切りを追加生成するために保持する。
    private let statusItemFactory: (String) -> any StatusItem

    public init(
        settings: SettingsStore,
        statusItemFactory: @escaping (String) -> any StatusItem
    ) {
        self.statusItemFactory = statusItemFactory

        // 生成順が並び順を決める: NSStatusItem は後から作られたものほど左に並ぶため、
        // メイン区切り（◇）→ サブ区切り（◆）の順に作ると
        // [常時非表示] ◆ [非表示] ◇ [表示]（時計側）の配置になる。
        let mainDivider = statusItemFactory(Self.mainDividerIdentifier)
        mainDivider.setIcon(
            symbolName: Self.mainDividerCollapsedSymbolName,
            accessibilityDescription: "Tsurara 非表示セクションの切り替え"
        )

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
        // length 拡大による collapse は #5（非表示）/#9（常時非表示）で導入されるため、
        // この時点では全セクションが見えている状態で初期化する。
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
    }
}
