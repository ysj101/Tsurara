import Foundation
import Testing
import TsuraraCore

private let sectionManagerToggleSuiteName = "TsuraraCoreTests.SectionManagerToggle"

private func makeToggleSettings(
    alwaysHiddenSectionEnabled: Bool = false
) -> SettingsStore {
    let defaults = UserDefaults(suiteName: sectionManagerToggleSuiteName)!
    defaults.removePersistentDomain(forName: sectionManagerToggleSuiteName)

    let settings = SettingsStore(defaults: defaults)
    settings.alwaysHiddenSectionEnabled = alwaysHiddenSectionEnabled
    return settings
}

@Suite(.serialized)
@MainActor
struct SectionManagerToggleTests {
    @Test
    func clickingMainDividerTogglesHiddenSectionAndIcon() {
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            mainDivider
        }

        #expect(mainDivider.iconSymbolNames == [
            SectionManager.mainDividerExpandedSymbolName
        ])

        mainDivider.fireClick()

        #expect(manager.isHiddenSectionCollapsed)
        #expect(manager.hiddenSection.isVisible == false)
        #expect(mainDivider.iconSymbolNames.last == SectionManager.mainDividerCollapsedSymbolName)
    }

    @Test
    func repeatedMainDividerClicksAlternateIcons() {
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            mainDivider
        }

        mainDivider.fireClick()
        mainDivider.fireClick()
        mainDivider.fireClick()
        mainDivider.fireClick()

        #expect(manager.isHiddenSectionCollapsed == false)
        #expect(mainDivider.iconSymbolNames == [
            SectionManager.mainDividerExpandedSymbolName,
            SectionManager.mainDividerCollapsedSymbolName,
            SectionManager.mainDividerExpandedSymbolName,
            SectionManager.mainDividerCollapsedSymbolName,
            SectionManager.mainDividerExpandedSymbolName,
        ])
    }

    @Test
    func visibleHiddenSectionCanBeCollapsed() {
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            mainDivider
        }

        #expect(manager.isHiddenSectionCollapsed == false)
        #expect(manager.hiddenSection.isVisible)

        manager.toggleHiddenSection()

        #expect(manager.isHiddenSectionCollapsed)
        #expect(manager.hiddenSection.isVisible == false)
        #expect(
            mainDivider.lengthHistory
                == [SectionManager.hiddenSectionCollapsedLength]
        )
        // 定数の同語反復にならない実質的な検証: 画面幅を超える拡大であること。
        #expect(mainDivider.length > 1_000)
    }

    @Test
    func collapsedHiddenSectionCanBeShown() {
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            mainDivider
        }
        manager.toggleHiddenSection()

        manager.toggleHiddenSection()

        #expect(manager.isHiddenSectionCollapsed == false)
        #expect(manager.hiddenSection.isVisible)
        #expect(
            mainDivider.lengthHistory
                == [
                    SectionManager.hiddenSectionCollapsedLength,
                    StatusItemLength.square,
                ]
        )
    }

    @Test
    func twoConsecutiveTogglesRestoreTheInitialState() {
        let initialLength: CGFloat = 42
        let mainDivider = MockStatusItem(length: initialLength)
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            mainDivider
        }

        manager.toggleHiddenSection()
        manager.toggleHiddenSection()

        #expect(manager.isHiddenSectionCollapsed == false)
        #expect(manager.hiddenSection.isVisible)
        #expect(mainDivider.length == initialLength)
        #expect(
            mainDivider.lengthHistory
                == [SectionManager.hiddenSectionCollapsedLength, initialLength]
        )

        // 奇数回目でも正しく collapse する（復元値の取り違えを検出）。
        manager.toggleHiddenSection()
        #expect(manager.isHiddenSectionCollapsed)
        #expect(
            mainDivider.lengthHistory
                == [
                    SectionManager.hiddenSectionCollapsedLength,
                    initialLength,
                    SectionManager.hiddenSectionCollapsedLength,
                ]
        )
    }

    @Test
    func togglingDoesNotChangeSecondaryDividerLength() {
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        let secondaryDivider = MockStatusItem(length: StatusItemLength.variable)
        var dividers = [mainDivider, secondaryDivider]
        let manager = SectionManager(
            settings: makeToggleSettings(alwaysHiddenSectionEnabled: true)
        ) { _ in
            dividers.removeFirst()
        }

        manager.toggleHiddenSection()
        manager.toggleHiddenSection()

        #expect(secondaryDivider.length == StatusItemLength.variable)
        #expect(secondaryDivider.lengthHistory.isEmpty)
        #expect(manager.alwaysHiddenSection.isVisible)
    }
}
