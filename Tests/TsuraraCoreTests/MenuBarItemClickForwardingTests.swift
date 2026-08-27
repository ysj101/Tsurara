import CoreGraphics
import Foundation
import Testing
import TsuraraCore

@MainActor
private final class StubClickWindowLister: MenuBarItemWindowListing {
    var snapshots: [[MenuBarItemWindow]]
    private(set) var callCount = 0

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
    var readyOnCheck: Int?
    private(set) var preparedWindowIDs: [CGWindowID] = []
    private(set) var readinessCheckCount = 0
    private(set) var restoreCount = 0

    func prepareForCapture(of windows: [MenuBarItemWindow]) -> Bool {
        preparedWindowIDs = windows.map(\.windowID)
        return didReposition
    }

    func isReadyForCapture(_ window: MenuBarItemWindow) -> Bool {
        readinessCheckCount += 1
        return readyOnCheck.map { readinessCheckCount >= $0 } ?? true
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
        let windowID: CGWindowID
    }

    var error: Error?
    private(set) var clicks: [SentClick] = []

    func sendClick(
        at point: CGPoint,
        button: MenuBarItemClickButton,
        ownerPID: pid_t,
        windowID: CGWindowID
    ) async throws {
        clicks.append(
            SentClick(
                point: point,
                button: button,
                ownerPID: ownerPID,
                windowID: windowID
            )
        )
        if let error { throw error }
    }
}

@MainActor
private final class StubInterfaceTracker: MenuBarItemInterfaceTracking {
    var error: Error?
    private(set) var prepareCount = 0
    private(set) var waitedOwnerPIDs: [pid_t] = []

    func prepareForClick() {
        prepareCount += 1
    }

    func waitUntilInterfaceDismissed(ownerPID: pid_t) async throws {
        waitedOwnerPIDs.append(ownerPID)
        if let error { throw error }
    }
}

@MainActor
private final class StubActivator: MenuBarItemAccessibilityActivating {
    struct Activation: Equatable {
        let point: CGPoint
        let itemFrame: CGRect
        let button: MenuBarItemClickButton
    }

    var ownerPID: pid_t?
    private(set) var activations: [Activation] = []

    init(ownerPID: pid_t?) {
        self.ownerPID = ownerPID
    }

    func activate(
        at point: CGPoint,
        itemFrame: CGRect,
        button: MenuBarItemClickButton
    ) -> pid_t? {
        activations.append(
            Activation(point: point, itemFrame: itemFrame, button: button)
        )
        return ownerPID
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
    sourceFrame: CGRect? = nil,
    ownerPID: pid_t = 123,
    order: Int = 0
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
        sourceFrame: sourceFrame,
        owner: MenuBarItemOwner(processIdentifier: ownerPID, name: "Example"),
        order: order
    )
}

private let clickDisplayFrames = [
    CGRect(x: -1_000, y: 0, width: 3_000, height: 1_080)
]

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
                    clickWindow(
                        id: 7,
                        frame: CGRect(x: -120, y: 0, width: 20, height: 24)
                    ),
                    clickWindow(frame: CGRect(x: -80, y: 0, width: 24, height: 24))
                ], [
                    clickWindow(
                        id: 8,
                        frame: CGRect(x: 350, y: 0, width: 20, height: 24)
                    ),
                    clickWindow(
                        id: 99,
                        frame: CGRect(x: 400, y: 0, width: 24, height: 24)
                    )
                ]]
            ),
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: tracker
        )

        try await controller.forwardClick(
            on: clickItem(
                frame: CGRect(x: 400, y: 0, width: 24, height: 24),
                sourceFrame: CGRect(x: -80, y: 0, width: 24, height: 24)
            ),
            button: .left,
            mainDividerFrame: CGRect(x: -50, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: clickDisplayFrames
        )

        #expect(positioner.preparedWindowIDs == [42])
        #expect(sender.clicks == [
            .init(
                point: CGPoint(x: 412, y: 12),
                button: .left,
                ownerPID: 123,
                windowID: 99
            )
        ])
        #expect(tracker.prepareCount == 1)
        #expect(tracker.waitedOwnerPIDs == [123])
        #expect(positioner.restoreCount == 1)
    }

    @Test
    func doesNotSendSyntheticClickWhenAccessibilityActivationSucceeds() async throws {
        let sender = StubClickSender()
        let activator = StubActivator(ownerPID: 456)
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(
                windows: [
                    clickWindow(frame: CGRect(x: 100, y: 0, width: 20, height: 24))
                ]
            ),
            positioner: StubClickPositioner(),
            clickSender: sender,
            interfaceTracker: StubInterfaceTracker(),
            activator: activator
        )

        try await controller.forwardClick(
            on: clickItem(frame: CGRect(x: 100, y: 0, width: 20, height: 24)),
            button: .left,
            mainDividerFrame: CGRect(x: 130, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: clickDisplayFrames
        )

        #expect(activator.activations.count == 1)
        #expect(sender.clicks.isEmpty)
    }

    @Test
    func tracksOwnerPIDResolvedByAccessibilityActivator() async throws {
        let tracker = StubInterfaceTracker()
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(
                windows: [
                    clickWindow(frame: CGRect(x: 100, y: 0, width: 20, height: 24))
                ]
            ),
            positioner: StubClickPositioner(),
            clickSender: StubClickSender(),
            interfaceTracker: tracker,
            activator: StubActivator(ownerPID: 456)
        )

        try await controller.forwardClick(
            on: clickItem(frame: CGRect(x: 100, y: 0, width: 20, height: 24)),
            button: .left,
            mainDividerFrame: CGRect(x: 130, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: clickDisplayFrames
        )

        #expect(tracker.prepareCount == 1)
        #expect(tracker.waitedOwnerPIDs == [456])
    }

    @Test
    func fallsBackToSyntheticClickAndTracksCGWindowOwner() async throws {
        let sender = StubClickSender()
        let tracker = StubInterfaceTracker()
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(
                windows: [
                    clickWindow(
                        id: 77,
                        frame: CGRect(x: 100, y: 0, width: 20, height: 24),
                        ownerPID: 123
                    )
                ]
            ),
            positioner: StubClickPositioner(),
            clickSender: sender,
            interfaceTracker: tracker,
            activator: StubActivator(ownerPID: nil)
        )

        try await controller.forwardClick(
            on: clickItem(
                id: 77,
                frame: CGRect(x: 100, y: 0, width: 20, height: 24),
                ownerPID: 123
            ),
            button: .right,
            mainDividerFrame: CGRect(x: 130, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: clickDisplayFrames
        )

        #expect(sender.clicks == [
            .init(
                point: CGPoint(x: 110, y: 12),
                button: .right,
                ownerPID: 123,
                windowID: 77
            )
        ])
        #expect(tracker.waitedOwnerPIDs == [123])
    }

    @Test
    func activatesAtFrameResolvedAfterTemporaryExpansion() async throws {
        let positioner = StubClickPositioner()
        positioner.didReposition = true
        let activator = StubActivator(ownerPID: 456)
        let expandedFrame = CGRect(x: 400, y: 2, width: 24, height: 22)
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(snapshots: [[
                clickWindow(
                    id: 41,
                    frame: CGRect(x: -100, y: 0, width: 20, height: 24)
                )
            ], [
                clickWindow(id: 84, frame: expandedFrame)
            ]]),
            positioner: positioner,
            clickSender: StubClickSender(),
            interfaceTracker: StubInterfaceTracker(),
            activator: activator
        )

        try await controller.forwardClick(
            on: clickItem(
                id: 41,
                frame: expandedFrame,
                sourceFrame: CGRect(x: -100, y: 0, width: 20, height: 24)
            ),
            button: .right,
            mainDividerFrame: CGRect(x: -50, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: clickDisplayFrames
        )

        #expect(activator.activations == [
            .init(
                point: CGPoint(x: 412, y: 13),
                itemFrame: expandedFrame,
                button: .right
            )
        ])
    }

    @Test
    func sendsWindowIDResolvedAfterTemporaryExpansion() async throws {
        let positioner = StubClickPositioner()
        positioner.didReposition = true
        let sender = StubClickSender()
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(snapshots: [[
                clickWindow(
                    id: 41,
                    frame: CGRect(x: -100, y: 0, width: 20, height: 24)
                )
            ], [
                clickWindow(
                    id: 84,
                    frame: CGRect(x: 400, y: 0, width: 20, height: 24)
                )
            ]]),
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: StubInterfaceTracker()
        )

        try await controller.forwardClick(
            on: clickItem(
                id: 41,
                frame: CGRect(x: 400, y: 0, width: 20, height: 24),
                sourceFrame: CGRect(x: -100, y: 0, width: 20, height: 24)
            ),
            button: .left,
            mainDividerFrame: CGRect(x: -50, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: clickDisplayFrames
        )

        #expect(sender.clicks.map(\.windowID) == [84])
    }

    @Test
    func resolvesShiftedSameOwnerItemByItsOwnerRelativeOrder() async throws {
        let positioner = StubClickPositioner()
        positioner.didReposition = true
        let sender = StubClickSender()
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(snapshots: [[
                clickWindow(id: 10, frame: CGRect(x: -140, y: 0, width: 20, height: 24)),
                clickWindow(id: 11, frame: CGRect(x: -100, y: 0, width: 20, height: 24)),
                clickWindow(id: 12, frame: CGRect(x: -60, y: 0, width: 20, height: 24)),
            ], [
                clickWindow(id: 20, frame: CGRect(x: 300, y: 0, width: 20, height: 24)),
                clickWindow(id: 21, frame: CGRect(x: 340, y: 0, width: 20, height: 24)),
                clickWindow(id: 22, frame: CGRect(x: 380, y: 0, width: 20, height: 24)),
            ]]),
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: StubInterfaceTracker()
        )

        try await controller.forwardClick(
            on: clickItem(
                id: 11,
                frame: CGRect(x: -100, y: 0, width: 20, height: 24),
                order: 1
            ),
            button: .left,
            mainDividerFrame: CGRect(x: -30, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: clickDisplayFrames
        )

        #expect(positioner.preparedWindowIDs == [11])
        #expect(sender.clicks == [
            .init(
                point: CGPoint(x: 350, y: 12),
                button: .left,
                ownerPID: 123,
                windowID: 21
            )
        ])
        #expect(positioner.restoreCount == 1)
    }

    @Test
    func resolvesHiddenItemWhenSameOwnerAlsoHasAnAlwaysHiddenItem() async throws {
        // 常時非表示セクションの区切りは撮像用の一時展開でも戻らないため、その
        // 項目だけ画面外に取り残される。owner 内 index を非表示セクションだけで
        // 数えると 1 つずれ、取り残された項目をクリックしてしまう。
        let positioner = StubClickPositioner()
        positioner.didReposition = true
        let sender = StubClickSender()
        let alwaysHidden = clickWindow(
            id: 9,
            frame: CGRect(x: -260, y: 0, width: 20, height: 24)
        )
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(snapshots: [[
                alwaysHidden,
                clickWindow(id: 2, frame: CGRect(x: -200, y: 0, width: 20, height: 24)),
                clickWindow(id: 11, frame: CGRect(x: -100, y: 0, width: 20, height: 24)),
            ], [
                alwaysHidden,
                clickWindow(id: 2, frame: CGRect(x: -200, y: 0, width: 20, height: 24)),
                clickWindow(id: 21, frame: CGRect(x: 340, y: 0, width: 20, height: 24)),
            ]]),
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: StubInterfaceTracker()
        )

        try await controller.forwardClick(
            on: clickItem(
                id: 11,
                frame: CGRect(x: -100, y: 0, width: 20, height: 24),
                order: 0
            ),
            button: .left,
            mainDividerFrame: CGRect(x: -30, y: 0, width: 20, height: 24),
            subDividerFrame: CGRect(x: -200, y: 0, width: 20, height: 24),
            displayFrames: clickDisplayFrames
        )

        #expect(positioner.preparedWindowIDs == [11])
        // 取り残された常時非表示項目 (x: -260) ではなく、展開後の項目を押す。
        #expect(sender.clicks == [
            .init(
                point: CGPoint(x: 350, y: 12),
                button: .left,
                ownerPID: 123,
                windowID: 21
            )
        ])
    }

    @Test
    func pollsUntilRepositionedTargetIsReadyBeforeClicking() async throws {
        let positioner = StubClickPositioner()
        positioner.didReposition = true
        positioner.readyOnCheck = 3
        let sender = StubClickSender()
        let lister = StubClickWindowLister(snapshots: [[
            clickWindow(frame: CGRect(x: -100, y: 0, width: 20, height: 24))
        ], [
            clickWindow(frame: CGRect(x: -60, y: 0, width: 20, height: 24))
        ], [
            clickWindow(frame: CGRect(x: -20, y: 0, width: 20, height: 24))
        ], [
            clickWindow(frame: CGRect(x: 400, y: 0, width: 20, height: 24))
        ]])
        let controller = MenuBarItemClickForwardingController(
            windowLister: lister,
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: StubInterfaceTracker(),
            repositionPollInterval: .zero,
            repositionPollLimit: 3
        )

        try await controller.forwardClick(
            on: clickItem(
                frame: CGRect(x: 400, y: 0, width: 20, height: 24),
                sourceFrame: CGRect(x: -100, y: 0, width: 20, height: 24)
            ),
            button: .left,
            mainDividerFrame: CGRect(x: -50, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: clickDisplayFrames
        )

        #expect(lister.callCount == 4)
        #expect(positioner.readinessCheckCount == 3)
        #expect(sender.clicks == [
            .init(
                point: CGPoint(x: 410, y: 12),
                button: .left,
                ownerPID: 123,
                windowID: 42
            )
        ])
        #expect(positioner.restoreCount == 1)
    }

    @Test
    func doesNotClickWhenRepositioningNeverBecomesReady() async {
        let positioner = StubClickPositioner()
        positioner.didReposition = true
        positioner.readyOnCheck = .max
        let sender = StubClickSender()
        let controller = MenuBarItemClickForwardingController(
            windowLister: StubClickWindowLister(
                windows: [
                    clickWindow(frame: CGRect(x: -100, y: 0, width: 20, height: 24))
                ]
            ),
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: StubInterfaceTracker(),
            repositionPollInterval: .zero,
            repositionPollLimit: 3
        )

        await #expect(
            throws: MenuBarItemClickForwardingError.itemNotFound(ownerPID: 123)
        ) {
            try await controller.forwardClick(
                on: clickItem(
                    frame: CGRect(x: 400, y: 0, width: 20, height: 24),
                    sourceFrame: CGRect(x: -100, y: 0, width: 20, height: 24)
                ),
                button: .left,
                mainDividerFrame: CGRect(x: -50, y: 0, width: 20, height: 24),
                subDividerFrame: nil,
                displayFrames: clickDisplayFrames
            )
        }

        // 上限まで待ってから諦めたことだけを見る（最後の部分結果の絞り込みで
        // もう一度判定されるため、厳密な回数には依存しない）。
        #expect(positioner.readinessCheckCount >= 3)
        #expect(sender.clicks.isEmpty)
        #expect(positioner.restoreCount == 1)
    }

    @Test
    func keepsPollingWhileRepositionedTargetIsMissingFromTheWindowList() async throws {
        let positioner = StubClickPositioner()
        positioner.didReposition = true
        let sender = StubClickSender()
        let lister = StubClickWindowLister(snapshots: [[
            clickWindow(frame: CGRect(x: -100, y: 0, width: 20, height: 24))
        ], [
            // 再配置の途中で対象が一瞬だけ列挙から消えるケース。
            clickWindow(
                id: 99,
                frame: CGRect(x: 200, y: 0, width: 20, height: 24),
                ownerPID: 999
            )
        ], [
            clickWindow(frame: CGRect(x: 400, y: 0, width: 20, height: 24))
        ]])
        let controller = MenuBarItemClickForwardingController(
            windowLister: lister,
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: StubInterfaceTracker(),
            repositionPollInterval: .zero,
            repositionPollLimit: 3
        )

        try await controller.forwardClick(
            on: clickItem(
                frame: CGRect(x: 400, y: 0, width: 20, height: 24),
                sourceFrame: CGRect(x: -100, y: 0, width: 20, height: 24)
            ),
            button: .left,
            mainDividerFrame: CGRect(x: -50, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: clickDisplayFrames
        )

        #expect(sender.clicks == [
            .init(
                point: CGPoint(x: 410, y: 12),
                button: .left,
                ownerPID: 123,
                windowID: 42
            )
        ])
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
            button: .right,
            mainDividerFrame: CGRect(x: 130, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: clickDisplayFrames
        )

        #expect(sender.clicks == [
            .init(
                point: CGPoint(x: 110, y: 13),
                button: .right,
                ownerPID: 123,
                windowID: 42
            )
        ])
        #expect(positioner.restoreCount == 0)
    }

    @Test
    func usesCapturedOrderToBreakEqualDistanceForSameOwner() async throws {
        let positioner = StubClickPositioner()
        let sender = StubClickSender()
        let lister = StubClickWindowLister(windows: [
            clickWindow(id: 41, frame: CGRect(x: 80, y: 0, width: 20, height: 24)),
            clickWindow(id: 42, frame: CGRect(x: 120, y: 0, width: 20, height: 24))
        ])
        let controller = MenuBarItemClickForwardingController(
            windowLister: lister,
            positioner: positioner,
            clickSender: sender,
            interfaceTracker: StubInterfaceTracker()
        )

        try await controller.forwardClick(
            on: clickItem(
                frame: CGRect(x: 100, y: 0, width: 20, height: 24),
                order: 1
            ),
            button: .left,
            mainDividerFrame: CGRect(x: 150, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: clickDisplayFrames
        )

        #expect(positioner.preparedWindowIDs == [42])
        #expect(sender.clicks.map(\.point.x) == [130])
        #expect(lister.callCount == 1)
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
                button: .left,
                mainDividerFrame: CGRect(x: 130, y: 0, width: 20, height: 24),
                subDividerFrame: nil,
                displayFrames: clickDisplayFrames
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
                on: clickItem(
                    frame: CGRect(x: 100, y: 0, width: 20, height: 20),
                    sourceFrame: CGRect(x: -100, y: 0, width: 20, height: 20)
                ),
                button: .left,
                mainDividerFrame: CGRect(x: -50, y: 0, width: 20, height: 24),
                subDividerFrame: nil,
                displayFrames: clickDisplayFrames
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
            throws: MenuBarItemClickForwardingError.itemNotFound(ownerPID: 123)
        ) {
            try await controller.forwardClick(
                on: clickItem(frame: CGRect(x: -100, y: 0, width: 20, height: 20)),
                button: .left,
                mainDividerFrame: CGRect(x: -50, y: 0, width: 20, height: 24),
                subDividerFrame: nil,
                displayFrames: clickDisplayFrames
            )
        }

        #expect(sender.clicks.isEmpty)
        #expect(positioner.restoreCount == 1)
    }
}
