import Foundation

@MainActor
public protocol RehideTimerScheduling: AnyObject {
    /// スケジュールと残時間計算の双方で使う単調増加時刻。
    var now: TimeInterval { get }

    /// このスケジューラ自身の時計で deadline までの残時間を求める。
    func remainingTime(until deadline: TimeInterval) -> TimeInterval

    func schedule(
        after seconds: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    )
    func cancel()
}

public extension RehideTimerScheduling {
    func remainingTime(until deadline: TimeInterval) -> TimeInterval {
        max(0, deadline - now)
    }
}

/// サブバーの自動クローズについて、発火と残時間計算に使う時計を一元管理する。
/// メイン RunLoop 上で動作し、Foundation のみで実装して Core を AppKit から独立させる。
@MainActor
public final class FoundationRehideTimerScheduler: RehideTimerScheduling {
    private var timer: Timer?

    public init() {}

    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    public func schedule(
        after seconds: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) {
        cancel()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                action()
            }
        }
        // .default モードだけだとメニュー追跡中（NSEventTrackingRunLoopMode）に
        // タイマーが止まり、メニュー保留ロジックへ到達できないため .common に載せる。
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }

    isolated deinit {
        timer?.invalidate()
    }
}
