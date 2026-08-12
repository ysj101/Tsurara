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
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                action()
            }
        }
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
