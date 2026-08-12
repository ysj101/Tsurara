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
