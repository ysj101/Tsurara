import Foundation
import Testing
import TsuraraCore

private let autoCloseSuiteName = "TsuraraCoreTests.AutoClose"

@MainActor
private final class ManualRehideTimer: RehideTimerScheduling {
    private var action: (@MainActor () -> Void)?
    private var cancelledActions: [@MainActor () -> Void] = []

    private(set) var now: TimeInterval = 0
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
        if let action {
            cancelledActions.append(action)
        }
        action = nil
    }

    func advance(by interval: TimeInterval) {
        now += interval
    }

    func fire() {
        let pendingAction = action
        action = nil
        pendingAction?()
    }

    func fireCancelled() {
        guard !cancelledActions.isEmpty else { return }
        cancelledActions.removeFirst()()
    }
}

@Suite(.serialized)
@MainActor
struct AutoCloseTests {
    private func makeManager(
        autoCloseEnabled: Bool = true,
        autoCloseSeconds: Int = 15
    ) -> (SectionManager, ManualRehideTimer, MockStatusItem) {
        let defaults = UserDefaults(suiteName: autoCloseSuiteName)!
        defaults.removePersistentDomain(forName: autoCloseSuiteName)

        let settings = SettingsStore(defaults: defaults)
        settings.autoCloseEnabled = autoCloseEnabled
        settings.autoCloseSeconds = autoCloseSeconds

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
        // 本番配線と同じく、toggle は現在状態を反転し、close は閉じるだけにする。
        manager.onSubBarToggleRequested = {
            manager.setSubBarOpen(!manager.isSubBarOpen)
        }
        manager.onSubBarCloseRequested = { manager.setSubBarOpen(false) }
        return (manager, timer, divider)
    }

    @Test
    func openSubBarIsAutomaticallyClosedAfterConfiguredDelay() {
        let (manager, timer, _) = makeManager(autoCloseSeconds: 20)

        manager.setSubBarOpen(true)

        #expect(manager.isSubBarOpen)
        #expect(timer.scheduledDelays == [20])

        timer.fire()

        #expect(manager.isSubBarOpen == false)
    }

    @Test
    func autoCloseRequestsIdempotentCloseInsteadOfToggle() {
        let (manager, timer, _) = makeManager()
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
    func disabledAutoCloseDoesNotScheduleOrClose() {
        let (manager, timer, _) = makeManager(autoCloseEnabled: false)

        manager.setSubBarOpen(true)

        #expect(timer.scheduledDelays.isEmpty)
        #expect(timer.isScheduled == false)

        timer.fire()

        #expect(manager.isSubBarOpen)
    }

    @Test
    func pauseDisablesTimerAndResumeUsesSameMonotonicClock() {
        let (manager, timer, _) = makeManager(autoCloseSeconds: 10)
        manager.setSubBarOpen(true)
        timer.advance(by: 4)
        manager.beginAutoClosePause(source: .menuTracking)

        #expect(manager.isSubBarOpen)
        #expect(manager.isAutoClosePaused)
        #expect(timer.isScheduled == false)
        #expect(timer.cancelCount == 1)

        // メニューを開いている時間は自動クローズまでの残り時間に含めない。
        timer.advance(by: 30)
        manager.endAutoClosePause(source: .menuTracking)

        #expect(timer.scheduledDelays == [10, 6])
        #expect(timer.isScheduled)

        timer.fire()
        #expect(manager.isSubBarOpen == false)
    }

    @Test
    func nestedPauseSourcesResumeOnlyAfterBalancedEnds() {
        let (manager, timer, _) = makeManager(autoCloseSeconds: 10)
        manager.setSubBarOpen(true)

        manager.beginAutoClosePause(source: .menuTracking)
        manager.beginAutoClosePause(source: .clickForwarding)
        manager.endAutoClosePause(source: .menuTracking)

        #expect(manager.autoClosePauseCount == 1)
        #expect(timer.isScheduled == false)

        manager.endAutoClosePause(source: .clickForwarding)

        #expect(manager.autoClosePauseCount == 0)
        #expect(timer.isScheduled)
    }

    @Test
    func unmatchedEndCannotConsumeAnotherSourcesPause() {
        let (manager, timer, _) = makeManager(autoCloseSeconds: 10)
        manager.setSubBarOpen(true)
        manager.beginAutoClosePause(source: .clickForwarding)

        manager.endAutoClosePause(source: .menuTracking)

        #expect(manager.autoClosePauseCount == 1)
        #expect(timer.isScheduled == false)

        manager.endAutoClosePause(source: .clickForwarding)
        #expect(timer.isScheduled)
    }

    @Test
    func resetPauseCounterRecoversFromMissingEnd() {
        let (manager, timer, _) = makeManager(autoCloseSeconds: 10)
        manager.setSubBarOpen(true)
        manager.beginAutoClosePause(source: .menuTracking)
        manager.beginAutoClosePause(source: .clickForwarding)

        manager.resetAutoClosePauses()

        #expect(manager.autoClosePauseCount == 0)
        #expect(timer.isScheduled)
    }

    @Test
    func openingDuringPauseWaitsToStartAutoCloseTimer() {
        let (manager, timer, _) = makeManager(autoCloseSeconds: 10)
        manager.beginAutoClosePause(source: .menuTracking)

        manager.setSubBarOpen(true)

        #expect(manager.isSubBarOpen)
        #expect(timer.scheduledDelays.isEmpty)
        timer.advance(by: 30)

        manager.endAutoClosePause(source: .menuTracking)

        #expect(timer.scheduledDelays == [10])
        timer.fire()
        #expect(manager.isSubBarOpen == false)
    }

    @Test
    func resumeAppliesGraceFloorWhenCountdownExpiredAtPause() {
        let (manager, timer, _) = makeManager(autoCloseSeconds: 10)
        manager.setSubBarOpen(true)
        timer.advance(by: 10)

        manager.beginAutoClosePause(source: .menuTracking)
        manager.endAutoClosePause(source: .menuTracking)

        #expect(timer.scheduledDelays == [10, 1.5])
    }

    @Test
    func changingIntervalFullyResetsOpenSubBarCountdown() {
        let defaults = UserDefaults(suiteName: autoCloseSuiteName)!
        defaults.removePersistentDomain(forName: autoCloseSuiteName)
        let settings = SettingsStore(defaults: defaults)
        settings.autoCloseEnabled = true
        settings.autoCloseSeconds = 10
        let timer = ManualRehideTimer()
        let manager = SectionManager(settings: settings, rehideTimer: timer) {
            _ in MockStatusItem(length: StatusItemLength.square)
        }
        manager.setSubBarOpen(true)
        timer.advance(by: 7)

        settings.autoCloseSeconds = 20
        manager.autoCloseSettingDidChange()

        // 設定変更時は残り3秒や割合を引き継がず、新しい全20秒に戻す。
        #expect(timer.scheduledDelays == [10, 20])
        #expect(timer.cancelCount == 1)
        #expect(timer.isScheduled)
    }

    @Test
    func cancelledTimerCallbackCannotCloseANewerOpenCycle() {
        let (manager, timer, _) = makeManager()
        manager.setSubBarOpen(true)
        manager.setSubBarOpen(false)
        manager.setSubBarOpen(true)

        timer.fireCancelled()

        #expect(manager.isSubBarOpen)
        #expect(timer.isScheduled)

        timer.fire()
        #expect(manager.isSubBarOpen == false)
    }

    @Test
    func disablingWhileTimerInFlightPreventsClose() {
        let defaults = UserDefaults(suiteName: autoCloseSuiteName)!
        defaults.removePersistentDomain(forName: autoCloseSuiteName)
        let settings = SettingsStore(defaults: defaults)
        settings.autoCloseEnabled = true
        let timer = ManualRehideTimer()
        let manager = SectionManager(
            settings: settings,
            rehideTimer: timer
        ) { _ in MockStatusItem(length: StatusItemLength.square) }
        manager.onSubBarCloseRequested = { manager.setSubBarOpen(false) }
        manager.setSubBarOpen(true)

        settings.autoCloseEnabled = false
        timer.fire()

        #expect(manager.isSubBarOpen)
    }
}
