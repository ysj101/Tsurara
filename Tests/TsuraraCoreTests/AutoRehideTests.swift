import Foundation
import Testing
import TsuraraCore

private let autoRehideSuiteName = "TsuraraCoreTests.AutoRehide"

@MainActor
private final class ManualRehideTimer: RehideTimerScheduling {
    private var action: (@MainActor () -> Void)?

    private(set) var scheduledDelays: [TimeInterval] = []
    private(set) var cancelCount = 0

    var isScheduled: Bool { action != nil }

    func schedule(
        after seconds: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) {
        scheduledDelays.append(seconds)
        self.action = action
    }

    func cancel() {
        cancelCount += 1
        action = nil
    }

    func fire() {
        let pendingAction = action
        action = nil
        pendingAction?()
    }
}

@Suite(.serialized)
@MainActor
struct AutoRehideTests {
    private func makeManager(
        autoRehideEnabled: Bool = true,
        autoRehideSeconds: Int = 15
    ) -> (SectionManager, ManualRehideTimer, MockStatusItem) {
        let defaults = UserDefaults(suiteName: autoRehideSuiteName)!
        defaults.removePersistentDomain(forName: autoRehideSuiteName)

        let settings = SettingsStore(defaults: defaults)
        settings.autoRehideEnabled = autoRehideEnabled
        settings.autoRehideSeconds = autoRehideSeconds

        let timer = ManualRehideTimer()
        let divider = MockStatusItem(length: StatusItemLength.square)
        let manager = SectionManager(
            settings: settings,
            rehideTimer: timer
        ) { _ in
            divider
        }
        return (manager, timer, divider)
    }

    @Test
    func shownSectionIsAutomaticallyRehiddenAfterConfiguredDelay() {
        let (manager, timer, _) = makeManager(autoRehideSeconds: 20)
        manager.toggleHiddenSection()

        manager.toggleHiddenSection()

        #expect(manager.isHiddenSectionCollapsed == false)
        #expect(timer.scheduledDelays == [20])

        timer.fire()

        #expect(manager.isHiddenSectionCollapsed)
        #expect(manager.hiddenSection.isVisible == false)
    }

    @Test
    func disabledAutoRehideDoesNotScheduleOrCollapse() {
        let (manager, timer, _) = makeManager(autoRehideEnabled: false)
        manager.toggleHiddenSection()

        manager.toggleHiddenSection()

        #expect(timer.scheduledDelays.isEmpty)
        #expect(timer.isScheduled == false)

        timer.fire()

        #expect(manager.isHiddenSectionCollapsed == false)
        #expect(manager.hiddenSection.isVisible)
    }

    @Test
    func menuTrackingDefersRehideUntilTrackingEndsAndTimerFiresAgain() {
        let (manager, timer, _) = makeManager(autoRehideSeconds: 10)
        manager.toggleHiddenSection()
        manager.toggleHiddenSection()
        manager.isMenuTrackingActive = true

        timer.fire()

        #expect(manager.isHiddenSectionCollapsed == false)
        #expect(timer.isScheduled == false)

        manager.isMenuTrackingActive = false

        #expect(timer.scheduledDelays == [10, 10])
        #expect(timer.isScheduled)

        timer.fire()

        #expect(manager.isHiddenSectionCollapsed)
    }

    @Test
    func manualRehideCancelsPendingTimerWithoutLaterSideEffects() {
        let (manager, timer, divider) = makeManager()
        manager.toggleHiddenSection()
        manager.toggleHiddenSection()
        #expect(timer.isScheduled)

        manager.toggleHiddenSection()

        #expect(manager.isHiddenSectionCollapsed)
        #expect(timer.cancelCount == 1)
        #expect(timer.isScheduled == false)
        let lengthHistoryAfterManualRehide = divider.lengthHistory

        timer.fire()

        #expect(manager.isHiddenSectionCollapsed)
        #expect(timer.cancelCount == 1)
        #expect(divider.lengthHistory == lengthHistoryAfterManualRehide)
    }

    @Test
    func disablingWhileTimerInFlightPreventsRehide() {
        let defaults = UserDefaults(suiteName: autoRehideSuiteName)!
        defaults.removePersistentDomain(forName: autoRehideSuiteName)
        defer { defaults.removePersistentDomain(forName: autoRehideSuiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.autoRehideEnabled = true

        let timer = ManualRehideTimer()
        let manager = SectionManager(
            settings: settings,
            rehideTimer: timer
        ) { _ in MockStatusItem(length: StatusItemLength.square) }

        manager.toggleHiddenSection()  // collapse
        manager.toggleHiddenSection()  // expand → schedule

        // 発火前に設定を無効化したら、発火しても再非表示しない。
        settings.autoRehideEnabled = false
        timer.fire()

        #expect(manager.isHiddenSectionCollapsed == false)
    }
}
