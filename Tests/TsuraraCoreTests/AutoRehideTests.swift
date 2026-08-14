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
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        let divider = MockStatusItem(length: StatusItemLength.square)
        var items = [toggleItem, divider]
        let manager = SectionManager(
            settings: settings,
            rehideTimer: timer
        ) { _ in
            items.removeFirst()
        }
        manager.onSubBarToggleRequested = { manager.setSubBarOpen(false) }
        return (manager, timer, divider)
    }

    @Test
    func openSubBarIsAutomaticallyClosedAfterConfiguredDelay() {
        let (manager, timer, _) = makeManager(autoRehideSeconds: 20)

        manager.setSubBarOpen(true)

        #expect(manager.isSubBarOpen)
        #expect(timer.scheduledDelays == [20])

        timer.fire()

        #expect(manager.isSubBarOpen == false)
    }

    @Test
    func disabledAutoRehideDoesNotScheduleOrClose() {
        let (manager, timer, _) = makeManager(autoRehideEnabled: false)

        manager.setSubBarOpen(true)

        #expect(timer.scheduledDelays.isEmpty)
        #expect(timer.isScheduled == false)

        timer.fire()

        #expect(manager.isSubBarOpen)
    }

    @Test
    func menuTrackingDefersCloseUntilTrackingEndsAndTimerFiresAgain() {
        let (manager, timer, _) = makeManager(autoRehideSeconds: 10)
        manager.setSubBarOpen(true)
        manager.isMenuTrackingActive = true

        timer.fire()

        #expect(manager.isSubBarOpen)
        #expect(timer.isScheduled == false)

        manager.isMenuTrackingActive = false

        #expect(timer.scheduledDelays == [10, 10])
        #expect(timer.isScheduled)

        timer.fire()

        #expect(manager.isSubBarOpen == false)
    }

    @Test
    func manualCloseCancelsPendingTimerWithoutLaterSideEffects() {
        let (manager, timer, divider) = makeManager()
        manager.setSubBarOpen(true)
        #expect(timer.isScheduled)

        manager.setSubBarOpen(false)

        #expect(timer.cancelCount == 1)
        #expect(timer.isScheduled == false)
        let lengthHistoryAfterManualClose = divider.lengthHistory

        timer.fire()

        #expect(manager.isSubBarOpen == false)
        #expect(timer.cancelCount == 1)
        #expect(divider.lengthHistory == lengthHistoryAfterManualClose)
    }

    @Test
    func disablingWhileTimerInFlightPreventsClose() {
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
        manager.onSubBarToggleRequested = { manager.setSubBarOpen(false) }
        manager.setSubBarOpen(true)

        settings.autoRehideEnabled = false
        timer.fire()

        #expect(manager.isSubBarOpen)
    }
}
