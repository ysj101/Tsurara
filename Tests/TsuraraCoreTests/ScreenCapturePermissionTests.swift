import Testing
import TsuraraCore

@MainActor
private final class MockScreenCapturePermissionManager: ScreenCapturePermissionManaging {
    var status: ScreenCapturePermissionStatus
    var requestResult: Bool
    private(set) var requestCount = 0

    init(
        status: ScreenCapturePermissionStatus,
        requestResult: Bool = false
    ) {
        self.status = status
        self.requestResult = requestResult
    }

    func requestAccess() -> Bool {
        requestCount += 1
        if requestResult {
            status = .authorized
        } else {
            status = .denied
        }
        return requestResult
    }
}

@Suite
@MainActor
struct ScreenCapturePermissionTests {
    @Test
    func authorizedPermissionOpensSubBarWithoutRequestingAgain() {
        let permission = MockScreenCapturePermissionManager(status: .authorized)
        let flow = ScreenCapturePermissionFlow(permission: permission)

        #expect(flow.actionForSubBarRequest() == .openSubBar)
        #expect(permission.requestCount == 0)
    }

    @Test
    func undeterminedPermissionShowsExplanationBeforeSystemRequest() {
        let permission = MockScreenCapturePermissionManager(status: .notDetermined)
        let flow = ScreenCapturePermissionFlow(permission: permission)

        #expect(flow.actionForSubBarRequest() == .showOnboarding)
        #expect(permission.requestCount == 0)
    }

    @Test
    func acceptingOnboardingRequestsPermissionAndOpensSubBarWhenGranted() {
        let permission = MockScreenCapturePermissionManager(
            status: .notDetermined,
            requestResult: true
        )
        let flow = ScreenCapturePermissionFlow(permission: permission)

        #expect(flow.requestAccessAfterOnboarding() == .openSubBar)
        #expect(permission.requestCount == 1)
    }

    @Test
    func rejectingSystemRequestShowsSettingsFallback() {
        let permission = MockScreenCapturePermissionManager(
            status: .notDetermined,
            requestResult: false
        )
        let flow = ScreenCapturePermissionFlow(permission: permission)

        #expect(flow.requestAccessAfterOnboarding() == .showDeniedFallback)
        #expect(permission.requestCount == 1)
    }

    @Test
    func deniedPermissionShowsSettingsFallbackWithoutRequestingAgain() {
        let permission = MockScreenCapturePermissionManager(status: .denied)
        let flow = ScreenCapturePermissionFlow(permission: permission)

        #expect(flow.actionForSubBarRequest() == .showDeniedFallback)
        #expect(permission.requestCount == 0)
    }
}
