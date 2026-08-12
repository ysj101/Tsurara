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
    func createsOnlyMainDividerByDefault() {
        withSettings { settings in
            var createdItems: [(identifier: String, item: MockStatusItem)] = []

            let manager = SectionManager(settings: settings) { identifier in
                let item = MockStatusItem()
                createdItems.append((identifier, item))
                return item
            }

            #expect(createdItems.count == 1)
            #expect(createdItems[0].identifier == SectionManager.mainDividerIdentifier)
            #expect(manager.hiddenSection.dividerItem === createdItems[0].item)
            #expect(manager.alwaysHiddenSection.dividerItem == nil)
            #expect(createdItems[0].item.iconSymbolNames == [
                SectionManager.mainDividerExpandedSymbolName
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

            #expect(createdItems.count == 2)
            // 生成順 = 並び順の契約: メイン区切りが先、サブ区切りが後（より左）。
            #expect(createdItems[0].identifier == SectionManager.mainDividerIdentifier)
            #expect(createdItems[1].identifier == SectionManager.subDividerIdentifier)
            #expect(manager.hiddenSection.dividerItem === createdItems[0].item)
            #expect(manager.alwaysHiddenSection.dividerItem === createdItems[1].item)
            #expect(createdItems[1].item.iconSymbolNames == [
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
