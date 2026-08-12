/// メニューバーを区切る各領域の種別。
public enum MenuBarSectionKind: CaseIterable, Sendable {
    case visible
    case hidden
    case alwaysHidden
}

/// 1 つのメニューバーセクションと、その左端に置く区切りアイテムを表す。
@MainActor
public final class MenuBarSection {
    public let kind: MenuBarSectionKind
    public var isVisible: Bool
    public let dividerItem: (any StatusItem)?

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
