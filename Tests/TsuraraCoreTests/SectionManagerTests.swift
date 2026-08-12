import Foundation
import Testing
import TsuraraCore

private let sectionManagerSuiteName = "TsuraraCoreTests.SectionManager"

private func makeSettings(alwaysHiddenSectionEnabled: Bool = false) -> SettingsStore {
    let defaults = UserDefaults(suiteName: sectionManagerSuiteName)!
    defaults.removePersistentDomain(forName: sectionManagerSuiteName)

    let settings = SettingsStore(defaults: defaults)
    settings.alwaysHiddenSectionEnabled = alwaysHiddenSectionEnabled
    return settings
}

@Suite(.serialized)
@MainActor
struct SectionManagerTests {
    @Test
    func createsOnlyMainDividerByDefault() {
        let settings = makeSettings()
        var createdItems: [MockStatusItem] = []

        let manager = SectionManager(settings: settings) {
            let item = MockStatusItem()
            createdItems.append(item)
            return item
        }

        #expect(createdItems.count == 1)
        #expect(manager.hiddenSection.dividerItem === createdItems[0])
        #expect(manager.alwaysHiddenSection.dividerItem == nil)
        #expect(createdItems[0].iconSymbolNames == ["chevron.compact.left"])
    }

    @Test
    func createsMainAndSecondaryDividersWhenAlwaysHiddenIsEnabled() {
        let settings = makeSettings(alwaysHiddenSectionEnabled: true)
        var createdItems: [MockStatusItem] = []

        let manager = SectionManager(settings: settings) {
            let item = MockStatusItem()
            createdItems.append(item)
            return item
        }

        #expect(createdItems.count == 2)
        #expect(manager.hiddenSection.dividerItem === createdItems[0])
        #expect(manager.alwaysHiddenSection.dividerItem === createdItems[1])
        #expect(createdItems[1].iconSymbolNames == ["diamond"])
    }

    @Test(arguments: [false, true])
    func sectionsHaveExpectedInitialState(alwaysHiddenSectionEnabled: Bool) {
        let settings = makeSettings(
            alwaysHiddenSectionEnabled: alwaysHiddenSectionEnabled
        )

        let manager = SectionManager(settings: settings) { MockStatusItem() }

        #expect(manager.visibleSection.kind == .visible)
        #expect(manager.visibleSection.isVisible)
        #expect(manager.visibleSection.dividerItem == nil)

        #expect(manager.hiddenSection.kind == .hidden)
        #expect(manager.hiddenSection.isVisible)
        #expect(manager.hiddenSection.dividerItem != nil)

        #expect(manager.alwaysHiddenSection.kind == .alwaysHidden)
        #expect(manager.alwaysHiddenSection.isVisible == false)
        #expect(
            (manager.alwaysHiddenSection.dividerItem != nil)
                == alwaysHiddenSectionEnabled
        )

        let dividerItems = [
            manager.hiddenSection.dividerItem,
            manager.alwaysHiddenSection.dividerItem,
        ].compactMap { $0 as? MockStatusItem }
        #expect(dividerItems.allSatisfy { $0.lengthHistory.isEmpty })
        #expect(dividerItems.allSatisfy { $0.isVisible })
    }
}
