import Foundation

@MainActor
public protocol RehideTimerScheduling: AnyObject {
    func schedule(
        after seconds: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    )
    func cancel()
}

/// アプリで使用するメイン RunLoop 上のタイマー。
/// Foundation のみで実装し、TsuraraCore を AppKit から独立させる。
@MainActor
public final class FoundationRehideTimerScheduler: RehideTimerScheduling {
    private var timer: Timer?

    public init() {}

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
