import Foundation
import Testing
import TsuraraCore

private let permissionTestSuiteName = "TsuraraCoreTests.ScreenCapturePermission"

@Suite(.serialized)
@MainActor
struct ScreenCapturePermissionTests {
    @Test
    func preflightDerivesAuthorizedAndClearsStaleRequestFlag() {
        withPermissionManager(preflight: true, hasRequested: true) { manager, settings, _ in
            #expect(manager.status == .authorized)
            #expect(settings.hasRequestedScreenCaptureAccess == false)
        }
    }

    @Test
    func untouchedPermissionIsNotDetermined() {
        withPermissionManager(preflight: false) { manager, _, requestCount in
            #expect(manager.status == .notDetermined)
            #expect(requestCount() == 0)
        }
    }

    @Test
    func initialRequestReturningFalseRemainsDecisionPending() {
        withPermissionManager(preflight: false, requestResult: false) {
            manager, settings, requestCount in
            #expect(manager.requestAccess() == .decisionPending)
            #expect(requestCount() == 1)
            #expect(settings.hasRequestedScreenCaptureAccess == true)
            #expect(manager.status == .requestPreviouslyPresented)
        }
    }

    @Test
    func tccResetKeepsStateAmbiguousAndAllowsRequestAgain() {
        withPermissionManager(
            preflight: false,
            hasRequested: true,
            requestResult: false
        ) { manager, _, requestCount in
            // フラグだけで拒否とは断定しない。リセット後の初回プロンプトも
            // 再表示できるよう requestAccess への経路を残す。
            #expect(manager.status == .requestPreviouslyPresented)
            #expect(manager.requestAccess() == .decisionPending)
            #expect(requestCount() == 1)
        }
    }

    @Test
    func authorizedRequestClearsPresentedFlag() {
        withPermissionManager(preflight: false, requestResult: true) {
            manager, settings, requestCount in
            #expect(manager.requestAccess() == .authorized)
            #expect(requestCount() == 1)
            #expect(settings.hasRequestedScreenCaptureAccess == false)
        }
    }

    @Test
    func preflightChangeOverridesPersistedState() {
        var preflight = false
        withPermissionManager(
            preflightAccess: { preflight },
            hasRequested: true
        ) { manager, settings, _ in
            #expect(manager.status == .requestPreviouslyPresented)

            preflight = true
            #expect(manager.status == .authorized)
            #expect(settings.hasRequestedScreenCaptureAccess == false)
        }
    }

    private func withPermissionManager(
        preflight: Bool,
        hasRequested: Bool = false,
        requestResult: Bool = false,
        _ test: (
            ScreenCapturePermissionManager,
            SettingsStore,
            () -> Int
        ) -> Void
    ) {
        withPermissionManager(
            preflightAccess: { preflight },
            hasRequested: hasRequested,
            requestResult: requestResult,
            test
        )
    }

    private func withPermissionManager(
        preflightAccess: @escaping () -> Bool,
        hasRequested: Bool = false,
        requestResult: Bool = false,
        _ test: (
            ScreenCapturePermissionManager,
            SettingsStore,
            () -> Int
        ) -> Void
    ) {
        let defaults = UserDefaults(suiteName: permissionTestSuiteName)!
        defaults.removePersistentDomain(forName: permissionTestSuiteName)
        defer { defaults.removePersistentDomain(forName: permissionTestSuiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.hasRequestedScreenCaptureAccess = hasRequested
        var requestCount = 0
        let manager = ScreenCapturePermissionManager(
            settings: settings,
            preflightAccess: preflightAccess,
            requestAccess: {
                requestCount += 1
                return requestResult
            }
        )
        test(manager, settings, { requestCount })
    }
}
