@MainActor
public final class SectionManager {
    public let visibleSection: MenuBarSection
    public let hiddenSection: MenuBarSection
    public let alwaysHiddenSection: MenuBarSection

    public init(
        settings: SettingsStore,
        statusItemFactory: () -> any StatusItem
    ) {
        let mainDivider = statusItemFactory()
        mainDivider.setIcon(
            symbolName: "chevron.compact.left",
            accessibilityDescription: "Tsurara"
        )

        let secondaryDivider: (any StatusItem)?
        if settings.alwaysHiddenSectionEnabled {
            let item = statusItemFactory()
            item.setIcon(
                symbolName: "diamond",
                accessibilityDescription: "Tsurara Always Hidden Section"
            )
            secondaryDivider = item
        } else {
            secondaryDivider = nil
        }

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
    }
}
