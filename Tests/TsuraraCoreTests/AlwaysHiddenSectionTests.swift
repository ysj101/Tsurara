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
            let mainDivider = MockStatusItem(length: StatusItemLength.square)
            let subDivider = MockStatusItem(length: StatusItemLength.variable)
            var dividers = [mainDivider, subDivider]

            let manager = SectionManager(settings: settings) { _ in
                dividers.removeFirst()
            }

            #expect(subDivider.length == SectionManager.hiddenSectionCollapsedLength)
            #expect(subDivider.lengthHistory == [SectionManager.hiddenSectionCollapsedLength])
            #expect(manager.alwaysHiddenSection.isVisible == false)
        }
    }

    @Test
    func togglingHiddenSectionLeavesSubDividerCollapsed() {
        withAlwaysHiddenSettings(enabled: true) { settings in
            let mainDivider = MockStatusItem(length: StatusItemLength.square)
            let subDivider = MockStatusItem(length: StatusItemLength.variable)
            var dividers = [mainDivider, subDivider]
            let manager = SectionManager(settings: settings) { _ in
                dividers.removeFirst()
            }
            let historyAtLaunch = subDivider.lengthHistory

            manager.toggleHiddenSection()
            manager.toggleHiddenSection()

            #expect(subDivider.length == SectionManager.hiddenSectionCollapsedLength)
            #expect(subDivider.lengthHistory == historyAtLaunch)
        }
    }

    @Test
    func runtimeEnableAndDisableCreatesAndDisposesCollapsedDivider() {
        withAlwaysHiddenSettings(enabled: false) { settings in
            let mainDivider = MockStatusItem(length: StatusItemLength.square)
            let subDivider = MockStatusItem(length: StatusItemLength.variable)
            var createdIdentifiers: [String] = []
            let manager = SectionManager(settings: settings) { identifier in
                createdIdentifiers.append(identifier)
                return identifier == SectionManager.mainDividerIdentifier
                    ? mainDivider
                    : subDivider
            }

            manager.setAlwaysHiddenSectionEnabled(true)

            #expect(createdIdentifiers == [
                SectionManager.mainDividerIdentifier,
                SectionManager.subDividerIdentifier,
            ])
            #expect(manager.alwaysHiddenSection.dividerItem === subDivider)
            #expect(subDivider.length == SectionManager.hiddenSectionCollapsedLength)
            #expect(manager.alwaysHiddenSection.isVisible == false)
            #expect(settings.alwaysHiddenSectionEnabled)

            manager.setAlwaysHiddenSectionEnabled(false)

            #expect(subDivider.isVisible == false)
            #expect(manager.alwaysHiddenSection.dividerItem == nil)
            #expect(manager.alwaysHiddenSection.isVisible == false)
            #expect(settings.alwaysHiddenSectionEnabled == false)
        }
    }

    @Test
    func temporarilyShowThenRehideTransitionsSection() {
        withAlwaysHiddenSettings(enabled: true) { settings in
            let originalLength: CGFloat = 37
            let mainDivider = MockStatusItem(length: StatusItemLength.square)
            let subDivider = MockStatusItem(length: originalLength)
            var dividers = [mainDivider, subDivider]
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
