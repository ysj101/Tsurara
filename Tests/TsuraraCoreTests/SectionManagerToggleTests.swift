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
    func hiddenSectionStartsAndRemainsCollapsedWhenToggleIsClicked() {
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
        }
        var toggleRequestCount = 0
        manager.onSubBarToggleRequested = { toggleRequestCount += 1 }
        let lengthHistoryAtLaunch = mainDivider.lengthHistory

        toggleItem.fireClick()

        #expect(toggleRequestCount == 1)
        #expect(manager.hiddenSection.isVisible == false)
        #expect(mainDivider.length == SectionManager.hiddenSectionCollapsedLength)
        #expect(mainDivider.lengthHistory == lengthHistoryAtLaunch)
        #expect(toggleItem.iconSymbolNames == [SectionManager.toggleClosedSymbolName])
        #expect(mainDivider.iconSymbolNames == [SectionManager.mainDividerSymbolName])
    }

    @Test
    func reportedSubBarStateAlternatesStatusIcon() {
        let mainDivider = MockStatusItem(length: StatusItemLength.square)
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
        }

        manager.setSubBarOpen(true)
        #expect(manager.isSubBarOpen)
        manager.setSubBarOpen(false)
        #expect(manager.isSubBarOpen == false)
        manager.setSubBarOpen(true)

        #expect(toggleItem.iconSymbolNames == [
            SectionManager.toggleClosedSymbolName,
            SectionManager.toggleOpenSymbolName,
            SectionManager.toggleClosedSymbolName,
            SectionManager.toggleOpenSymbolName,
        ])
        #expect(mainDivider.lengthHistory == [SectionManager.hiddenSectionCollapsedLength])
    }

    @Test
    func repeatedToggleRequestsNeverRestoreMainDividerLength() {
        let initialLength: CGFloat = 42
        let mainDivider = MockStatusItem(length: initialLength)
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
        }
        var toggleRequestCount = 0
        manager.onSubBarToggleRequested = { toggleRequestCount += 1 }

        manager.toggleSubBar()
        manager.toggleSubBar()
        manager.toggleSubBar()

        #expect(toggleRequestCount == 3)
        #expect(manager.hiddenSection.isVisible == false)
        #expect(mainDivider.length == SectionManager.hiddenSectionCollapsedLength)
        #expect(mainDivider.lengthHistory == [SectionManager.hiddenSectionCollapsedLength])
        #expect((manager.toggleItem as? MockStatusItem)?.lengthHistory.isEmpty == true)
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

        manager.toggleSubBar()
        manager.toggleSubBar()

        #expect(secondaryDivider.length == SectionManager.hiddenSectionCollapsedLength)
        #expect(secondaryDivider.lengthHistory == lengthHistoryAtLaunch)
        #expect(manager.alwaysHiddenSection.isVisible == false)
    }

    @Test
    func toggleDuringCaptureExpansionRequestsSubBarAndRestoreRecollapsesDivider() {
        let initialLength: CGFloat = 42
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        let mainDivider = MockStatusItem(length: initialLength)
        var items = [toggleItem, mainDivider]
        let manager = SectionManager(settings: makeToggleSettings()) { _ in
            items.removeFirst()
        }
        var toggleRequestCount = 0
        manager.onSubBarToggleRequested = { toggleRequestCount += 1 }

        #expect(manager.beginCaptureExpansion())
        // 撮像用の一時展開中でも、トグルはサブバー開閉だけを要求する。
        toggleItem.fireClick()
        #expect(toggleRequestCount == 1)
        #expect(manager.hiddenSection.isVisible)
        #expect(mainDivider.length == initialLength)

        manager.endCaptureExpansion()

        #expect(manager.hiddenSection.isVisible == false)
        #expect(mainDivider.length == SectionManager.hiddenSectionCollapsedLength)
        #expect(toggleItem.iconSymbolNames.last == SectionManager.toggleClosedSymbolName)
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
            SectionManager.hiddenSectionCollapsedLength,
            StatusItemLength.square,
        ])
        manager.endCaptureExpansion()
        #expect(manager.hiddenSection.isVisible == false)
        #expect(mainDivider.length == SectionManager.hiddenSectionCollapsedLength)
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
        #expect(manager.beginCaptureExpansion())
        #expect(manager.beginCaptureExpansion())
        manager.endCaptureExpansion()

        #expect(manager.hiddenSection.isVisible)
        #expect(mainDivider.length == initialLength)

        manager.endCaptureExpansion()

        #expect(manager.hiddenSection.isVisible == false)
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

        #expect(mainDivider.length == SectionManager.hiddenSectionCollapsedLength)
        #expect(mainDivider.lengthHistory == historyAfterRestore)
    }
}
