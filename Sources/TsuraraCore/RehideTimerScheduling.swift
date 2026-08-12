import Foundation

@MainActor
public protocol RehideTimerScheduling: AnyObject {
    func schedule(
        after seconds: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    )
    func cancel()
}

/// The main-run-loop timer used by the application. Keeping this implementation
/// in TsuraraCore lets SectionManager remain independent of AppKit.
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
