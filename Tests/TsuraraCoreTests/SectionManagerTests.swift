import Foundation
import Testing
import TsuraraCore

private let sectionManagerSuiteName = "TsuraraCoreTests.SectionManager"

// alwaysHiddenSectionEnabled: nil は「未設定のまま（SettingsStore の既定値）」を意味する。
private func withSettings(
    alwaysHiddenSectionEnabled: Bool? = nil,
    _ test: (SettingsStore) throws -> Void
) rethrows {
    let defaults = UserDefaults(suiteName: sectionManagerSuiteName)!
    defaults.removePersistentDomain(forName: sectionManagerSuiteName)
    defer { defaults.removePersistentDomain(forName: sectionManagerSuiteName) }

    let settings = SettingsStore(defaults: defaults)
    if let alwaysHiddenSectionEnabled {
        settings.alwaysHiddenSectionEnabled = alwaysHiddenSectionEnabled
    }
    try test(settings)
}

@Suite(.serialized)
@MainActor
struct SectionManagerTests {
    @Test
    func createsToggleAndMainDividerByDefault() {
        withSettings { settings in
            var createdItems: [(identifier: String, item: MockStatusItem)] = []

            let manager = SectionManager(settings: settings) { identifier in
                let item = MockStatusItem()
                createdItems.append((identifier, item))
                return item
            }

            #expect(createdItems.count == 2)
            #expect(createdItems[0].identifier == SectionManager.toggleItemIdentifier)
            #expect(createdItems[1].identifier == SectionManager.mainDividerIdentifier)
            #expect(manager.toggleItem === createdItems[0].item)
            #expect(manager.hiddenSection.dividerItem === createdItems[1].item)
            #expect(manager.alwaysHiddenSection.dividerItem == nil)
            #expect(createdItems[0].item.iconSymbolNames == [
                SectionManager.toggleExpandedSymbolName
            ])
            #expect(createdItems[1].item.iconSymbolNames == [
                SectionManager.mainDividerSymbolName
            ])
        }
    }

    @Test
    func createsMainAndSecondaryDividersWhenAlwaysHiddenIsEnabled() {
        withSettings(alwaysHiddenSectionEnabled: true) { settings in
            var createdItems: [(identifier: String, item: MockStatusItem)] = []

            let manager = SectionManager(settings: settings) { identifier in
                let item = MockStatusItem()
                createdItems.append((identifier, item))
                return item
            }

            #expect(createdItems.count == 3)
            // 生成順 = 並び順の契約: トグル、メイン、サブ（より左）の順。
            #expect(createdItems[0].identifier == SectionManager.toggleItemIdentifier)
            #expect(createdItems[1].identifier == SectionManager.mainDividerIdentifier)
            #expect(createdItems[2].identifier == SectionManager.subDividerIdentifier)
            #expect(manager.toggleItem === createdItems[0].item)
            #expect(manager.hiddenSection.dividerItem === createdItems[1].item)
            #expect(manager.alwaysHiddenSection.dividerItem === createdItems[2].item)
            #expect(createdItems[2].item.iconSymbolNames == [
                SectionManager.subDividerSymbolName
            ])
        }
    }

    @Test(arguments: [false, true])
    func sectionsHaveExpectedInitialState(alwaysHiddenSectionEnabled: Bool) {
        withSettings(alwaysHiddenSectionEnabled: alwaysHiddenSectionEnabled) { settings in
            let manager = SectionManager(settings: settings) { _ in MockStatusItem() }

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
        }
    }
}
