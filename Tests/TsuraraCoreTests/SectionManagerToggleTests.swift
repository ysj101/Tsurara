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
    func clickingToggleItemTogglesHiddenSectionAndIcon() {
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
        }

        #expect(toggleItem.iconSymbolNames == [
            SectionManager.toggleExpandedSymbolName
        ])
        #expect(mainDivider.iconSymbolNames == [SectionManager.mainDividerSymbolName])

        toggleItem.fireClick()

        #expect(manager.isHiddenSectionCollapsed)
        #expect(manager.hiddenSection.isVisible == false)
        #expect(mainDivider.length == SectionManager.hiddenSectionCollapsedLength)
        #expect(
            toggleItem.iconSymbolNames.last
                == SectionManager.toggleCollapsedSymbolName
        )
        #expect(mainDivider.iconSymbolNames == [SectionManager.mainDividerSymbolName])
    }

    @Test
    func repeatedToggleItemClicksAlternateIcons() {
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
        }

        toggleItem.fireClick()
        toggleItem.fireClick()
        toggleItem.fireClick()
        toggleItem.fireClick()

        #expect(manager.isHiddenSectionCollapsed == false)
        #expect(toggleItem.iconSymbolNames == [
            SectionManager.toggleExpandedSymbolName,
            SectionManager.toggleCollapsedSymbolName,
            SectionManager.toggleExpandedSymbolName,
            SectionManager.toggleCollapsedSymbolName,
            SectionManager.toggleExpandedSymbolName,
        ])
    }

    @Test
    func visibleHiddenSectionCanBeCollapsed() {
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
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
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
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
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
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

        // トグル項目自身の length は決して変更されない（このリファクタの中心不変条件）。
        #expect((manager.toggleItem as? MockStatusItem)?.lengthHistory.isEmpty == true)

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
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        let secondaryDivider = MockStatusItem(length: StatusItemLength.variable)
        var dividers = [toggleItem, mainDivider, secondaryDivider]
        let manager = SectionManager(
            settings: makeToggleSettings(alwaysHiddenSectionEnabled: true)
        ) { _ in
            dividers.removeFirst()
        }
        let lengthHistoryAtLaunch = secondaryDivider.lengthHistory

        manager.toggleHiddenSection()
        manager.toggleHiddenSection()

        #expect(secondaryDivider.length == SectionManager.hiddenSectionCollapsedLength)
        #expect(secondaryDivider.lengthHistory == lengthHistoryAtLaunch)
        #expect(manager.alwaysHiddenSection.isVisible == false)
    }

    @Test
    func toggleDuringCaptureExpansionIsMergedOnRestore() {
        let initialLength: CGFloat = 42
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        let mainDivider = MockStatusItem(windowID: 31, length: initialLength)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
        }

        #expect(manager.beginCaptureExpansion())
        // 撮像中は実際の UI を展開したままにし、ユーザー操作を最終状態へ合流する。
        toggleItem.fireClick()
        #expect(manager.hiddenSection.isVisible)
        #expect(mainDivider.length == initialLength)

        manager.endCaptureExpansion()

        #expect(manager.isHiddenSectionCollapsed)
        #expect(manager.hiddenSection.isVisible == false)
        #expect(mainDivider.length == SectionManager.hiddenSectionCollapsedLength)
        #expect(toggleItem.iconSymbolNames.last == SectionManager.toggleCollapsedSymbolName)
    }

    @Test
    func captureExpansionPulsesDividerEvenWhenAlreadyAtExpandedLength() {
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
        }

        #expect(manager.beginCaptureExpansion())

        #expect(mainDivider.lengthHistory == [
            SectionManager.hiddenSectionCollapsedLength,
            StatusItemLength.square,
        ])
        manager.endCaptureExpansion()
        #expect(manager.hiddenSection.isVisible)
        #expect(mainDivider.length == StatusItemLength.square)
    }

    @Test
    func overlappingCaptureExpansionsRestoreOnlyAfterLastOwnerFinishes() {
        let initialLength: CGFloat = 42
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        let mainDivider = MockStatusItem(length: initialLength)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
        }
        manager.toggleHiddenSection()

        #expect(manager.beginCaptureExpansion())
        #expect(manager.beginCaptureExpansion())
        manager.endCaptureExpansion()

        #expect(manager.hiddenSection.isVisible)
        #expect(mainDivider.length == initialLength)

        manager.endCaptureExpansion()

        #expect(manager.isHiddenSectionCollapsed)
        #expect(mainDivider.length == SectionManager.hiddenSectionCollapsedLength)
    }

    @Test
    func extraExpansionEndDoesNotAlterRestoredState() {
        let initialLength: CGFloat = 42
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        let mainDivider = MockStatusItem(length: initialLength)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
        }

        #expect(manager.beginCaptureExpansion())
        manager.endCaptureExpansion()
        let historyAfterRestore = mainDivider.lengthHistory

        manager.endCaptureExpansion()

        #expect(mainDivider.length == initialLength)
        #expect(mainDivider.lengthHistory == historyAfterRestore)
    }
}
