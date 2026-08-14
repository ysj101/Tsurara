/// メニューバーを区切る各領域の種別。
public enum MenuBarSectionKind: Sendable {
    case visible
    case hidden
    case alwaysHidden
}

/// 1 つのメニューバーセクションと、その左端に置く区切りアイテムを表す。
@MainActor
public final class MenuBarSection {
    public let kind: MenuBarSectionKind
    /// `.hidden` / `.alwaysHidden` では恒常的な画面上の可視性ではなく、
    /// SectionManager が一時展開している間だけ true になる。
    public internal(set) var isVisible: Bool
    public internal(set) var dividerItem: (any StatusItem)?

    public init(
        kind: MenuBarSectionKind,
        isVisible: Bool,
        dividerItem: (any StatusItem)?
    ) {
        self.kind = kind
        self.isVisible = isVisible
        self.dividerItem = dividerItem
    }
}
