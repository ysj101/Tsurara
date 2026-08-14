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

@MainActor
private final class ManualRehideClock {
    var now: TimeInterval = 0

    func advance(by interval: TimeInterval) {
        now += interval
    }
}

@Suite(.serialized)
@MainActor
struct AutoRehideTests {
    private func makeManager(
        autoRehideEnabled: Bool = true,
        autoRehideSeconds: Int = 15
    ) -> (SectionManager, ManualRehideTimer, ManualRehideClock, MockStatusItem) {
        let defaults = UserDefaults(suiteName: autoRehideSuiteName)!
        defaults.removePersistentDomain(forName: autoRehideSuiteName)

        let settings = SettingsStore(defaults: defaults)
        settings.autoRehideEnabled = autoRehideEnabled
        settings.autoRehideSeconds = autoRehideSeconds

        let timer = ManualRehideTimer()
        let clock = ManualRehideClock()
        let toggleItem = MockStatusItem(length: StatusItemLength.square)
        let divider = MockStatusItem(length: StatusItemLength.square)
        var items = [toggleItem, divider]
        let manager = SectionManager(
            settings: settings,
            rehideTimer: timer,
            currentTime: { clock.now }
        ) { _ in
            items.removeFirst()
        }
        // 本番配線と同じく、toggle は現在状態を反転し、close は閉じるだけにする。
        manager.onSubBarToggleRequested = {
            manager.setSubBarOpen(!manager.isSubBarOpen)
        }
        manager.onSubBarCloseRequested = { manager.setSubBarOpen(false) }
        return (manager, timer, clock, divider)
    }

    @Test
    func openSubBarIsAutomaticallyClosedAfterConfiguredDelay() {
        let (manager, timer, _, _) = makeManager(autoRehideSeconds: 20)

        manager.setSubBarOpen(true)

        #expect(manager.isSubBarOpen)
        #expect(timer.scheduledDelays == [20])

        timer.fire()

        #expect(manager.isSubBarOpen == false)
    }

    @Test
    func autoRehideRequestsIdempotentCloseInsteadOfToggle() {
        let (manager, timer, _, _) = makeManager()
        var toggleRequestCount = 0
        var closeRequestCount = 0
        manager.onSubBarToggleRequested = {
            toggleRequestCount += 1
            manager.setSubBarOpen(!manager.isSubBarOpen)
        }
        manager.onSubBarCloseRequested = {
            closeRequestCount += 1
            manager.setSubBarOpen(false)
        }
        manager.setSubBarOpen(true)

        timer.fire()

        #expect(toggleRequestCount == 0)
        #expect(closeRequestCount == 1)
        #expect(manager.isSubBarOpen == false)
    }

    @Test
    func disabledAutoRehideDoesNotScheduleOrClose() {
        let (manager, timer, _, _) = makeManager(autoRehideEnabled: false)

        manager.setSubBarOpen(true)

        #expect(timer.scheduledDelays.isEmpty)
        #expect(timer.isScheduled == false)

        timer.fire()

        #expect(manager.isSubBarOpen)
    }

    @Test
    func menuTrackingPausesTimerAndResumesWithRemainingDelay() {
        let (manager, timer, clock, _) = makeManager(autoRehideSeconds: 10)
        manager.setSubBarOpen(true)
        clock.advance(by: 4)
        manager.isMenuTrackingActive = true

        #expect(manager.isSubBarOpen)
        #expect(timer.isScheduled == false)
        #expect(timer.cancelCount == 1)

        // メニューを開いている時間は自動クローズまでの残り時間に含めない。
        clock.advance(by: 30)

        manager.isMenuTrackingActive = false

        #expect(timer.scheduledDelays == [10, 6])
        #expect(timer.isScheduled)

        timer.fire()

        #expect(manager.isSubBarOpen == false)
    }

    @Test
    func openingDuringMenuTrackingWaitsToStartAutoCloseTimer() {
        let (manager, timer, clock, _) = makeManager(autoRehideSeconds: 10)
        manager.isMenuTrackingActive = true

        manager.setSubBarOpen(true)

        #expect(manager.isSubBarOpen)
        #expect(timer.scheduledDelays.isEmpty)
        clock.advance(by: 30)

        manager.isMenuTrackingActive = false

        #expect(timer.scheduledDelays == [10])
        timer.fire()
        #expect(manager.isSubBarOpen == false)
    }

    @Test
    func manualCloseCancelsPendingTimerWithoutLaterSideEffects() {
        let (manager, timer, _, divider) = makeManager()
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
        manager.onSubBarToggleRequested = {
            manager.setSubBarOpen(!manager.isSubBarOpen)
        }
        manager.onSubBarCloseRequested = { manager.setSubBarOpen(false) }
        manager.setSubBarOpen(true)

        settings.autoRehideEnabled = false
        timer.fire()

        #expect(manager.isSubBarOpen)
    }
}
