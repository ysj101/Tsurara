import Foundation
import Testing
import TsuraraCore

private let alwaysHiddenSectionSuiteName = "TsuraraCoreTests.AlwaysHiddenSection"

private func withAlwaysHiddenSettings(
    enabled: Bool,
    _ test: (SettingsStore) throws -> Void
) rethrows {
    let defaults = UserDefaults(suiteName: alwaysHiddenSectionSuiteName)!
    defaults.removePersistentDomain(forName: alwaysHiddenSectionSuiteName)
    defer { defaults.removePersistentDomain(forName: alwaysHiddenSectionSuiteName) }

    let settings = SettingsStore(defaults: defaults)
    settings.alwaysHiddenSectionEnabled = enabled
    try test(settings)
}

@Suite(.serialized)
@MainActor
struct AlwaysHiddenSectionTests {
    @Test
    func enabledSectionStartsCollapsedAtLaunch() {
        withAlwaysHiddenSettings(enabled: true) { settings in
            let toggleItem = MockStatusItem(length: StatusItemLength.square)
            let mainDivider = MockStatusItem(length: StatusItemLength.square)
            let subDivider = MockStatusItem(length: StatusItemLength.variable)
            var dividers = [toggleItem, mainDivider, subDivider]

            let manager = SectionManager(settings: settings) { _ in
                dividers.removeFirst()
            }

            #expect(subDivider.length == SectionManager.hiddenSectionCollapsedLength)
            #expect(subDivider.lengthHistory == [SectionManager.hiddenSectionCollapsedLength])
            #expect(manager.alwaysHiddenSection.isVisible == false)
        }
    }

    @Test
    func togglingSubBarLeavesSubDividerCollapsed() {
        withAlwaysHiddenSettings(enabled: true) { settings in
            let toggleItem = MockStatusItem(length: StatusItemLength.square)
            let mainDivider = MockStatusItem(length: StatusItemLength.square)
            let subDivider = MockStatusItem(length: StatusItemLength.variable)
            var dividers = [toggleItem, mainDivider, subDivider]
            let manager = SectionManager(settings: settings) { _ in
                dividers.removeFirst()
            }
            let historyAtLaunch = subDivider.lengthHistory

            manager.toggleSubBar()
            manager.toggleSubBar()

            #expect(subDivider.length == SectionManager.hiddenSectionCollapsedLength)
            #expect(subDivider.lengthHistory == historyAtLaunch)
        }
    }

    @Test
    func runtimeEnableAndDisableCreatesAndDisposesCollapsedDivider() {
        withAlwaysHiddenSettings(enabled: false) { settings in
            let toggleItem = MockStatusItem(length: StatusItemLength.square)
            let mainDivider = MockStatusItem(length: StatusItemLength.square)
            let subDivider = MockStatusItem(length: StatusItemLength.variable)
            var createdIdentifiers: [String] = []
            let manager = SectionManager(settings: settings) { identifier in
                createdIdentifiers.append(identifier)
                if identifier == SectionManager.toggleItemIdentifier {
                    return toggleItem
                }
                return identifier == SectionManager.mainDividerIdentifier
                    ? mainDivider
                    : subDivider
            }

            manager.setAlwaysHiddenSectionEnabled(true)

            #expect(createdIdentifiers == [
                SectionManager.toggleItemIdentifier,
                SectionManager.mainDividerIdentifier,
                SectionManager.subDividerIdentifier,
            ])
            #expect(manager.alwaysHiddenSection.dividerItem === subDivider)
            #expect(subDivider.length == SectionManager.hiddenSectionCollapsedLength)
            #expect(manager.alwaysHiddenSection.isVisible == false)
            #expect(settings.alwaysHiddenSectionEnabled)

            manager.setAlwaysHiddenSectionEnabled(false)

            // 参照を手放すだけでなく、ステータスバーから確実に取り除く。
            #expect(subDivider.isRemoved)
            #expect(manager.alwaysHiddenSection.dividerItem == nil)
            #expect(manager.alwaysHiddenSection.isVisible == false)
            #expect(settings.alwaysHiddenSectionEnabled == false)
        }
    }

    @Test
    func reenablingAfterDisableCreatesFreshDivider() {
        withAlwaysHiddenSettings(enabled: false) { settings in
            var created: [MockStatusItem] = []
            let manager = SectionManager(settings: settings) { _ in
                let item = MockStatusItem(length: StatusItemLength.variable)
                created.append(item)
                return item
            }

            manager.setAlwaysHiddenSectionEnabled(true)
            manager.setAlwaysHiddenSectionEnabled(false)
            manager.setAlwaysHiddenSectionEnabled(true)

            // toggle + main + サブ区切り 2 回で計 4 個。破棄済みの個体は再利用しない。
            #expect(created.count == 4)
            #expect(created[2].isRemoved)
            let current = manager.alwaysHiddenSection.dividerItem as? MockStatusItem
            #expect(current === created[3])
            #expect(current?.isRemoved == false)
            #expect(current?.isVisible == true)
            #expect(current?.length == SectionManager.hiddenSectionCollapsedLength)
        }
    }

    @Test
    func disablingTemporarilyShownSectionRecollapsesMainDivider() {
        withAlwaysHiddenSettings(enabled: true) { settings in
            let toggleItem = MockStatusItem(length: StatusItemLength.square)
            let mainDivider = MockStatusItem(length: 31)
            let subDivider = MockStatusItem(length: 37)
            var dividers = [toggleItem, mainDivider, subDivider]
            let manager = SectionManager(settings: settings) { _ in
                dividers.removeFirst()
            }
            manager.temporarilyShowAlwaysHiddenSection()

            manager.setAlwaysHiddenSectionEnabled(false)

            #expect(manager.hiddenSection.isVisible == false)
            #expect(mainDivider.length == SectionManager.hiddenSectionCollapsedLength)
            #expect(subDivider.isRemoved)
        }
    }

    @Test
    func togglingSubBarRehidesTemporarilyShownSection() {
        withAlwaysHiddenSettings(enabled: true) { settings in
            let toggleItem = MockStatusItem(length: StatusItemLength.square)
            let mainDivider = MockStatusItem(length: StatusItemLength.square)
            let subDivider = MockStatusItem(length: 37)
            var dividers = [toggleItem, mainDivider, subDivider]
            let manager = SectionManager(settings: settings) { _ in
                dividers.removeFirst()
            }

            manager.temporarilyShowAlwaysHiddenSection()
            #expect(manager.alwaysHiddenSection.isVisible)

            // サブバー操作に戻ると、一時表示中の常時非表示セクションも畳まれる。
            manager.toggleSubBar()

            #expect(manager.alwaysHiddenSection.isVisible == false)
            #expect(subDivider.length == SectionManager.hiddenSectionCollapsedLength)
            #expect(manager.hiddenSection.isVisible == false)
            #expect(mainDivider.length == SectionManager.hiddenSectionCollapsedLength)
        }
    }

    @Test
    func temporarilyShowThenRehideTransitionsSection() {
        withAlwaysHiddenSettings(enabled: true) { settings in
            let originalLength: CGFloat = 37
            let toggleItem = MockStatusItem(length: StatusItemLength.square)
            let mainDivider = MockStatusItem(length: StatusItemLength.square)
            let subDivider = MockStatusItem(length: originalLength)
            var dividers = [toggleItem, mainDivider, subDivider]
            let manager = SectionManager(settings: settings) { _ in
                dividers.removeFirst()
            }

            manager.temporarilyShowAlwaysHiddenSection()

            #expect(subDivider.length == originalLength)
            #expect(manager.alwaysHiddenSection.isVisible)

            manager.rehideAlwaysHiddenSection()

            #expect(subDivider.length == SectionManager.hiddenSectionCollapsedLength)
            #expect(manager.alwaysHiddenSection.isVisible == false)
            #expect(subDivider.lengthHistory == [
                SectionManager.hiddenSectionCollapsedLength,
                originalLength,
                SectionManager.hiddenSectionCollapsedLength,
            ])
        }
    }
}
