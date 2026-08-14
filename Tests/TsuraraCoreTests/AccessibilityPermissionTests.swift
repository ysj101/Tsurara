import Foundation
import Testing
import TsuraraCore

private let accessibilityPermissionSuiteName =
    "TsuraraCoreTests.AccessibilityPermission"

@Suite(.serialized)
@MainActor
struct AccessibilityPermissionTests {
    @Test
    func untouchedPermissionIsNotDeterminedWithoutRequesting() {
        withManager(preflight: false) { manager, _, requestCount in
            #expect(manager.status == .notDetermined)
            #expect(requestCount() == 0)
        }
    }

    @Test
    func initialFalseResultIsPendingInsteadOfDenied() {
        withManager(preflight: false, requestResult: false) {
            manager, settings, requestCount in
            #expect(manager.status == .notDetermined)
            #expect(manager.requestAccess() == .decisionPending)
            #expect(requestCount() == 1)
            #expect(settings.hasRequestedAccessibilityAccess)
            #expect(manager.status == .requestPreviouslyPresented)
        }
    }

    @Test
    func laterPreflightAuthorizationClearsPresentedFlag() {
        var preflight = false
        withManager(
            preflightAccess: { preflight },
            hasRequested: true
        ) { manager, settings, _ in
            #expect(manager.status == .requestPreviouslyPresented)

            preflight = true
            #expect(manager.status == .authorized)
            #expect(settings.hasRequestedAccessibilityAccess == false)
        }
    }

    @Test
    func immediatelyAuthorizedRequestClearsPresentedFlag() {
        withManager(preflight: false, requestResult: true) {
            manager, settings, _ in
            #expect(manager.requestAccess() == .authorized)
            #expect(settings.hasRequestedAccessibilityAccess == false)
        }
    }

    @Test
    func previouslyPresentedPermissionCanBeRequestedAgain() {
        withManager(
            preflight: false,
            hasRequested: true,
            requestResult: false
        ) { manager, settings, requestCount in
            #expect(manager.status == .requestPreviouslyPresented)
            #expect(manager.requestAccess() == .decisionPending)
            #expect(requestCount() == 1)
            #expect(settings.hasRequestedAccessibilityAccess)
        }
    }

    private func withManager(
        preflight: Bool,
        hasRequested: Bool = false,
        requestResult: Bool = false,
        _ test: (
            AccessibilityPermissionManager,
            SettingsStore,
            () -> Int
        ) -> Void
    ) {
        withManager(
            preflightAccess: { preflight },
            hasRequested: hasRequested,
            requestResult: requestResult,
            test
        )
    }

    private func withManager(
        preflightAccess: @escaping () -> Bool,
        hasRequested: Bool = false,
        requestResult: Bool = false,
        _ test: (
            AccessibilityPermissionManager,
            SettingsStore,
            () -> Int
        ) -> Void
    ) {
        let defaults = UserDefaults(suiteName: accessibilityPermissionSuiteName)!
        defaults.removePersistentDomain(forName: accessibilityPermissionSuiteName)
        defer {
            defaults.removePersistentDomain(forName: accessibilityPermissionSuiteName)
        }

        let settings = SettingsStore(defaults: defaults)
        settings.hasRequestedAccessibilityAccess = hasRequested
        var requestCount = 0
        let manager = AccessibilityPermissionManager(
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
