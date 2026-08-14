import CoreGraphics
import Foundation
import Testing
import TsuraraCore

@MainActor
private final class StubClickWindowLister: MenuBarItemWindowListing {
    var snapshots: [[MenuBarItemWindow]]
    private var callCount = 0

    init(windows: [MenuBarItemWindow]) {
        snapshots = [windows]
    }

    init(snapshots: [[MenuBarItemWindow]]) {
        self.snapshots = snapshots
    }

    func listMenuBarItemWindows() throws -> [MenuBarItemWindow] {
        defer { callCount += 1 }
        return snapshots[min(callCount, snapshots.count - 1)]
    }
}

@MainActor
private final class StubClickPositioner: MenuBarItemCapturePositioning {
    var didReposition = false
    private(set) var preparedWindowIDs: [CGWindowID] = []
    private(set) var restoreCount = 0

    func prepareForCapture(of windows: [MenuBarItemWindow]) -> Bool {
        preparedWindowIDs = windows.map(\.windowID)
        return didReposition
    }

    func restoreAfterCapture() {
        restoreCount += 1
    }
}

@MainActor
private final class StubClickSender: MenuBarItemClickSending {
    struct SentClick: Equatable {
        let point: CGPoint
        let button: MenuBarItemClickButton
        let ownerPID: pid_t
    }

    var error: Error?
    private(set) var clicks: [SentClick] = []

    func sendClick(
        at point: CGPoint,
        button: MenuBarItemClickButton,
        ownerPID: pid_t
    ) async throws {
        clicks.append(SentClick(point: point, button: button, ownerPID: ownerPID))
        if let error { throw error }
    }
}

@MainActor
private final class StubInterfaceTracker: MenuBarItemInterfaceTracking {
    var error: Error?
    private(set) var preparedOwnerPIDs: [pid_t] = []
    private(set) var waitCount = 0

    func prepareForClick(ownerPID: pid_t) {
        preparedOwnerPIDs.append(ownerPID)
    }

    func waitUntilInterfaceDismissed() async throws {
        waitCount += 1
        if let error { throw error }
    }
}

@MainActor
private func clickWindow(
    id: CGWindowID = 42,
    frame: CGRect,
    ownerPID: pid_t = 123
) -> MenuBarItemWindow {
    MenuBarItemWindow(
        windowID: id,
        frame: frame,
        owner: MenuBarItemOwner(
            processIdentifier: ownerPID,
            name: "Example"
        )
    )
}

private func clickItem(
    id: CGWindowID = 42,
    frame: CGRect,
    ownerPID: pid_t = 123
) -> ImagedMenuBarItem {
    ImagedMenuBarItem(
        windowID: id,
        image: CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: CGDataProvider(data: Data([0, 0, 0, 0]) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!,
        frame: frame,
        owner: MenuBarItemOwner(processIdentifier: ownerPID, name: "Example"),
        order: 0
    )
}

@Suite
@MainActor
struct MenuBarItemClickForwardingTests {
    @Test
    func repositionsRelistsClicksAndRestoresAfterInterfaceDismisses() async throws {
        let positioner = StubClickPositioner()
        positioner.didReposition = true
        let sender = StubClickSender()
        let tracker = StubInterfaceTracker()
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(
                snapshots: [[
                    clickWindow(frame: CGRect(x: -80, y: 0, width: 24, height: 24))
                ], [
                    clickWindow(frame: CGRect(x: 400, y: 0, width: 24, height: 24))
                ]]
            ),
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: tracker
        )

        try await controller.forwardClick(
            on: clickItem(frame: CGRect(x: -80, y: 0, width: 24, height: 24)),
            button: .left
        )

        #expect(positioner.preparedWindowIDs == [42])
        #expect(sender.clicks == [
            .init(point: CGPoint(x: 412, y: 12), button: .left, ownerPID: 123)
        ])
        #expect(tracker.preparedOwnerPIDs == [123])
        #expect(tracker.waitCount == 1)
        #expect(positioner.restoreCount == 1)
    }

    @Test
    func forwardsRightClickWithoutRestoringWhenNoRepositionWasNeeded() async throws {
        let positioner = StubClickPositioner()
        let sender = StubClickSender()
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(
                windows: [
                    clickWindow(frame: CGRect(x: 100, y: 2, width: 20, height: 22))
                ]
            ),
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: StubInterfaceTracker()
        )

        try await controller.forwardClick(
            on: clickItem(frame: CGRect(x: 100, y: 2, width: 20, height: 22)),
            button: .right
        )

        #expect(sender.clicks == [
            .init(point: CGPoint(x: 110, y: 13), button: .right, ownerPID: 123)
        ])
        #expect(positioner.restoreCount == 0)
    }

    @Test
    func restoresRepositioningWhenClickSendingFails() async {
        struct SendFailure: Error {}

        let positioner = StubClickPositioner()
        positioner.didReposition = true
        let sender = StubClickSender()
        sender.error = SendFailure()
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(
                windows: [clickWindow(frame: CGRect(x: 100, y: 0, width: 20, height: 20))]
            ),
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: StubInterfaceTracker()
        )

        await #expect(throws: SendFailure.self) {
            try await controller.forwardClick(
                on: clickItem(frame: CGRect(x: -100, y: 0, width: 20, height: 20)),
                button: .left
            )
        }

        #expect(positioner.restoreCount == 1)
    }

    @Test
    func restoresRepositioningWhenInterfaceTrackingIsCancelled() async {
        let positioner = StubClickPositioner()
        positioner.didReposition = true
        let tracker = StubInterfaceTracker()
        tracker.error = CancellationError()
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(
                snapshots: [[
                    clickWindow(frame: CGRect(x: -100, y: 0, width: 20, height: 20))
                ], [
                    clickWindow(frame: CGRect(x: 100, y: 0, width: 20, height: 20))
                ]]
            ),
            positioner: positioner,
            clickSender: StubClickSender(),
            interfaceTracker: tracker
        )

        await #expect(throws: CancellationError.self) {
            try await controller.forwardClick(
                on: clickItem(frame: CGRect(x: 100, y: 0, width: 20, height: 20)),
                button: .left
            )
        }

        #expect(positioner.restoreCount == 1)
    }

    @Test
    func failsSafelyWhenTargetWindowCanNoLongerBeResolved() async {
        let positioner = StubClickPositioner()
        positioner.didReposition = true
        let sender = StubClickSender()
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(snapshots: [[
                clickWindow(frame: CGRect(x: -100, y: 0, width: 20, height: 20))
            ], []]),
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: StubInterfaceTracker()
        )

        await #expect(
            throws: MenuBarItemClickForwardingError.windowNotFound(windowID: 42)
        ) {
            try await controller.forwardClick(
                on: clickItem(frame: CGRect(x: -100, y: 0, width: 20, height: 20)),
                button: .left
            )
        }

        #expect(sender.clicks.isEmpty)
        #expect(positioner.restoreCount == 1)
    }
}
