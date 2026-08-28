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
    var eventLog: ((String) -> Void)?

    func prepareForCapture(of windows: [MenuBarItemWindow]) -> Bool {
        eventLog?("expand")
        preparedWindowIDs = windows.map(\.windowID)
        return didReposition
    }

    func isReadyForCapture(_ window: MenuBarItemWindow) -> Bool {
        readinessCheckCount += 1
        return readyOnCheck.map { readinessCheckCount >= $0 } ?? true
    }

    func restoreAfterCapture() {
        eventLog?("restoreExpansion")
        restoreCount += 1
    }
}

@MainActor
private final class StubMover: MenuBarItemMoving {
    struct Move: Equatable {
        let itemID: CGWindowID
        let destination: MenuBarItemMoveDestination
    }

    struct StubFailure: Error {}

    var failuresByCallIndex: [Int: MenuBarItemMoveFailure] = [:]
    var returnedWindowsByCallIndex: [Int: MenuBarItemWindow] = [:]
    var eventLog: ((String) -> Void)?
    private(set) var moves: [Move] = []
    private(set) var suppliedWindows: [[MenuBarItemWindow]?] = []

    func move(
        _ item: MenuBarItemWindow,
        to destination: MenuBarItemMoveDestination,
        in windows: [MenuBarItemWindow]? = nil
    ) async throws(MenuBarItemMoveFailure) -> MenuBarItemWindow {
        let callIndex = moves.count
        moves.append(.init(itemID: item.windowID, destination: destination))
        suppliedWindows.append(windows)
        eventLog?(callIndex == 0 ? "moveOut" : "moveBack")
        if let failure = failuresByCallIndex[callIndex] {
            throw failure
        }
        return returnedWindowsByCallIndex[callIndex] ?? item
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
    var eventLog: ((String) -> Void)?

    func prepareForClick() {
        prepareCount += 1
    }

    func waitUntilInterfaceDismissed(ownerPID: pid_t) async throws {
        eventLog?("wait")
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
    var error: Error?
    var eventLog: ((String) -> Void)?
    private(set) var activations: [Activation] = []

    init(ownerPID: pid_t?) {
        self.ownerPID = ownerPID
    }

    func activate(
        at point: CGPoint,
        itemFrame: CGRect,
        button: MenuBarItemClickButton
    ) throws -> pid_t? {
        eventLog?("activate")
        activations.append(
            Activation(point: point, itemFrame: itemFrame, button: button)
        )
        if let error { throw error }
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

@MainActor
private func makeMovingController(
    windowLister: StubClickWindowLister,
    mover: StubMover,
    positioner: StubClickPositioner = StubClickPositioner(),
    clickSender: StubClickSender = StubClickSender(),
    interfaceTracker: StubInterfaceTracker = StubInterfaceTracker(),
    activator: StubActivator? = nil,
    repositionPollLimit: Int = 2,
    restorationAttemptLimit: Int = 3,
    restorationRetryDelay: Duration = .milliseconds(100)
) -> MenuBarItemClickForwardingController {
    if mover.returnedWindowsByCallIndex[0] == nil {
        mover.returnedWindowsByCallIndex[0] = temporaryMoveVisibleTarget
    }
    return MenuBarItemClickForwardingController(
        windowLister: windowLister,
        positioner: positioner,
        clickSender: clickSender,
        interfaceTracker: interfaceTracker,
        activator: activator,
        mover: mover,
        repositionPollInterval: .zero,
        repositionPollLimit: repositionPollLimit,
        restorationAttemptLimit: restorationAttemptLimit,
        restorationRetryDelay: restorationRetryDelay
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
            toggleFrame: nil,
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
            toggleFrame: nil,
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
            toggleFrame: nil,
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
            toggleFrame: nil,
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
            toggleFrame: nil,
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
            toggleFrame: nil,
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
            toggleFrame: nil,
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
            toggleFrame: nil,
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
            toggleFrame: nil,
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
                toggleFrame: nil,
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
            toggleFrame: nil,
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
            toggleFrame: nil,
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
            toggleFrame: nil,
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
                toggleFrame: nil,
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
                toggleFrame: nil,
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
                toggleFrame: nil,
                displayFrames: clickDisplayFrames
            )
        }

        #expect(sender.clicks.isEmpty)
        #expect(positioner.restoreCount == 1)
    }

    @Test
    func movesOneItemActivatesWaitsAndMovesItBackInOrder() async throws {
        var events: [String] = []
        let mover = StubMover()
        mover.eventLog = { events.append($0) }
        let activator = StubActivator(ownerPID: 123)
        activator.eventLog = { events.append($0) }
        let tracker = StubInterfaceTracker()
        tracker.eventLog = { events.append($0) }
        let initial = temporaryMoveInitialWindows
        let moved = temporaryMoveVisibleWindows
        let controller = makeMovingController(
            windowLister: StubClickWindowLister(
                snapshots: [initial, moved, moved]
            ),
            mover: mover,
            interfaceTracker: tracker,
            activator: activator,
            repositionPollLimit: 2
        )

        try await controller.forwardClick(
            on: temporaryMoveItem,
            button: .left,
            mainDividerFrame: temporaryMoveMainDivider.frame,
            subDividerFrame: nil,
            toggleFrame: temporaryMoveToggle.frame,
            displayFrames: clickDisplayFrames
        )

        #expect(events == ["moveOut", "activate", "wait", "moveBack"])
        #expect(mover.moves == [
            .init(
                itemID: 42,
                destination: .leftOf(
                    anchorFrame: temporaryMoveToggle.frame,
                    anchorWindowID: nil
                )
            ),
            .init(
                itemID: 42,
                destination: .leftOf(
                    anchorFrame: temporaryMoveRightNeighbor.frame,
                    anchorWindowID: temporaryMoveRightNeighbor.windowID
                )
            ),
        ])
    }

    @Test
    func movesItemBackWhenActivationThrows() async {
        struct ActivationFailure: Error {}

        var events: [String] = []
        let mover = StubMover()
        mover.eventLog = { events.append($0) }
        let activator = StubActivator(ownerPID: nil)
        activator.error = ActivationFailure()
        activator.eventLog = { events.append($0) }
        let moved = temporaryMoveVisibleWindows
        let controller = makeMovingController(
            windowLister: StubClickWindowLister(
                snapshots: [temporaryMoveInitialWindows, moved, moved]
            ),
            mover: mover,
            activator: activator,
            repositionPollLimit: 2
        )

        await #expect(throws: ActivationFailure.self) {
            try await controller.forwardClick(
                on: temporaryMoveItem,
                button: .left,
                mainDividerFrame: temporaryMoveMainDivider.frame,
                subDividerFrame: nil,
                toggleFrame: temporaryMoveToggle.frame,
                displayFrames: clickDisplayFrames
            )
        }

        #expect(events == ["moveOut", "activate", "moveBack"])
    }

    @Test
    func restoresWhenMoveOutIsCancelledAfterPosting() async {
        var events: [String] = []
        let mover = StubMover()
        mover.failuresByCallIndex = [
            0: .indeterminate(CancellationError())
        ]
        mover.eventLog = { events.append($0) }
        let sender = StubClickSender()
        let controller = makeMovingController(
            windowLister: StubClickWindowLister(
                snapshots: [
                    temporaryMoveInitialWindows,
                    temporaryMoveInitialWindows,
                ]
            ),
            mover: mover,
            clickSender: sender,
            restorationRetryDelay: .zero
        )

        await #expect(throws: CancellationError.self) {
            try await controller.forwardClick(
                on: temporaryMoveItem,
                button: .left,
                mainDividerFrame: temporaryMoveMainDivider.frame,
                subDividerFrame: nil,
                toggleFrame: temporaryMoveToggle.frame,
                displayFrames: clickDisplayFrames
            )
        }

        #expect(events == ["moveOut", "moveBack"])
        #expect(sender.clicks.isEmpty)
    }

    @Test
    func waitsForIndeterminateMoveOutToSettleBeforeRestoring() async {
        let mover = StubMover()
        mover.failuresByCallIndex = [
            0: .indeterminate(CancellationError())
        ]
        let lister = StubClickWindowLister(snapshots: [
            temporaryMoveInitialWindows,
            temporaryMoveInitialWindows,
            temporaryMoveVisibleWindows,
            temporaryMoveVisibleWindows,
        ])
        let controller = makeMovingController(
            windowLister: lister,
            mover: mover,
            repositionPollLimit: 2,
            restorationRetryDelay: .zero
        )

        await #expect(throws: CancellationError.self) {
            try await controller.forwardClick(
                on: temporaryMoveItem,
                button: .left,
                mainDividerFrame: temporaryMoveMainDivider.frame,
                subDividerFrame: nil,
                toggleFrame: temporaryMoveToggle.frame,
                displayFrames: clickDisplayFrames
            )
        }

        #expect(mover.moves.count == 2)
        #expect(
            mover.suppliedWindows[1]?.first(where: { $0.windowID == 42 })?.frame
                == temporaryMoveVisibleTarget.frame
        )
        #expect(lister.callCount == 4)
    }

    @Test
    func restorationReResolvesRightThenLeftThenDivider() async throws {
        let left = clickWindow(
            id: 41,
            frame: CGRect(x: -130, y: 0, width: 20, height: 24),
            ownerPID: 410
        )
        let initial = [
            left,
            clickWindow(
                id: 42,
                frame: CGRect(x: -100, y: 0, width: 20, height: 24)
            ),
            temporaryMoveRightNeighbor,
        ]
        let movedTarget = clickWindow(
            id: 42,
            frame: CGRect(x: 250, y: 0, width: 20, height: 24)
        )
        let moved = [left, temporaryMoveRightNeighbor, movedTarget]
        let mover = StubMover()
        mover.failuresByCallIndex = [
            1: .indeterminate(StubMover.StubFailure()),
            2: .indeterminate(StubMover.StubFailure()),
        ]
        let controller = makeMovingController(
            windowLister: StubClickWindowLister(snapshots: [
                initial,
                moved,
                [left, movedTarget],
                [movedTarget],
            ]),
            mover: mover,
            activator: StubActivator(ownerPID: 123),
            repositionPollLimit: 2,
            restorationAttemptLimit: 3,
            restorationRetryDelay: .zero
        )

        try await controller.forwardClick(
            on: temporaryMoveItem,
            button: .left,
            mainDividerFrame: temporaryMoveMainDivider.frame,
            subDividerFrame: nil,
            toggleFrame: temporaryMoveToggle.frame,
            displayFrames: clickDisplayFrames
        )

        #expect(mover.moves.map(\.destination) == [
            .leftOf(
                anchorFrame: temporaryMoveToggle.frame,
                anchorWindowID: nil
            ),
            .leftOf(
                anchorFrame: temporaryMoveRightNeighbor.frame,
                anchorWindowID: temporaryMoveRightNeighbor.windowID
            ),
            .rightOf(
                anchorFrame: left.frame,
                anchorWindowID: left.windowID
            ),
            .leftOf(
                anchorFrame: temporaryMoveMainDivider.frame,
                anchorWindowID: nil
            ),
        ])
    }

    @Test
    func movedPathUsesExactWindowReturnedByMoverInsteadOfOwnerIndex() async throws {
        let sameOwner = clickWindow(
            id: 40,
            frame: CGRect(x: -140, y: 0, width: 20, height: 24)
        )
        let wrongWindow = clickWindow(
            id: 99,
            frame: CGRect(x: 220, y: 0, width: 20, height: 24)
        )
        let exactWindow = clickWindow(
            id: 42,
            frame: CGRect(x: 250, y: 0, width: 20, height: 24)
        )
        let initial = [
            sameOwner,
            clickWindow(
                id: 42,
                frame: CGRect(x: -100, y: 0, width: 20, height: 24)
            ),
            temporaryMoveRightNeighbor,
        ]
        let activator = StubActivator(ownerPID: 123)
        let mover = StubMover()
        mover.returnedWindowsByCallIndex[0] = exactWindow
        let controller = makeMovingController(
            windowLister: StubClickWindowLister(snapshots: [
                initial,
                [sameOwner, wrongWindow, temporaryMoveRightNeighbor],
            ]),
            mover: mover,
            activator: activator,
            repositionPollLimit: 3,
            restorationRetryDelay: .zero
        )

        try await controller.forwardClick(
            on: temporaryMoveItem,
            button: .left,
            mainDividerFrame: temporaryMoveMainDivider.frame,
            subDividerFrame: nil,
            toggleFrame: temporaryMoveToggle.frame,
            displayFrames: clickDisplayFrames
        )

        #expect(activator.activations.map(\.itemFrame) == [exactWindow.frame])
    }

    @Test
    func retriesRestorationAndReportsWhenAllAttemptsFail() async {
        let mover = StubMover()
        mover.failuresByCallIndex = [
            1: .indeterminate(StubMover.StubFailure()),
            2: .indeterminate(StubMover.StubFailure()),
            3: .indeterminate(StubMover.StubFailure()),
        ]
        let moved = temporaryMoveVisibleWindows
        let controller = makeMovingController(
            windowLister: StubClickWindowLister(
                snapshots: [temporaryMoveInitialWindows, moved, moved]
            ),
            mover: mover,
            activator: StubActivator(ownerPID: 123),
            repositionPollLimit: 2,
            restorationAttemptLimit: 3
        )

        await #expect(
            throws: MenuBarItemClickForwardingError.itemRestorationFailed(
                ownerPID: 123
            )
        ) {
            try await controller.forwardClick(
                on: temporaryMoveItem,
                button: .left,
                mainDividerFrame: temporaryMoveMainDivider.frame,
                subDividerFrame: nil,
                toggleFrame: temporaryMoveToggle.frame,
                displayFrames: clickDisplayFrames
            )
        }

        #expect(mover.moves.count == 4)
    }

    @Test
    func fallsBackToLengthExpansionWhenMoveOutFails() async throws {
        var events: [String] = []
        let mover = StubMover()
        mover.failuresByCallIndex = [
            0: .notMoved(StubMover.StubFailure())
        ]
        mover.eventLog = { events.append($0) }
        let positioner = StubClickPositioner()
        positioner.didReposition = true
        positioner.eventLog = { events.append($0) }
        let expanded = temporaryMoveVisibleWindows
        let controller = makeMovingController(
            windowLister: StubClickWindowLister(
                snapshots: [
                    temporaryMoveInitialWindows,
                    expanded,
                ]
            ),
            mover: mover,
            positioner: positioner,
            repositionPollLimit: 1
        )

        try await controller.forwardClick(
            on: temporaryMoveItem,
            button: .left,
            mainDividerFrame: temporaryMoveMainDivider.frame,
            subDividerFrame: nil,
            toggleFrame: temporaryMoveToggle.frame,
            displayFrames: clickDisplayFrames
        )

        #expect(events == ["moveOut", "expand", "restoreExpansion"])
        #expect(positioner.restoreCount == 1)
    }

    @Test
    func choosesReturnAnchorByRightThenLeftThenMainDivider() {
        let left = clickWindow(
            id: 10,
            frame: CGRect(x: -140, y: 0, width: 20, height: 24),
            ownerPID: 10
        )
        let target = clickWindow(
            id: 20,
            frame: CGRect(x: -100, y: 0, width: 20, height: 24),
            ownerPID: 20
        )
        let right = clickWindow(
            id: 30,
            frame: CGRect(x: -60, y: 0, width: 20, height: 24),
            ownerPID: 30
        )

        let anchors = MenuBarItemReturnAnchors.computing(
            for: target,
            in: [right, target, left],
            mainDividerFrame: temporaryMoveMainDivider.frame
        )
        #expect(
            anchors.destination(currentWindows: [right, left]) == .leftOf(
                anchorFrame: right.frame,
                anchorWindowID: right.windowID
            )
        )
        #expect(
            anchors.destination(currentWindows: [left]) == .rightOf(
                anchorFrame: left.frame,
                anchorWindowID: left.windowID
            )
        )
        #expect(
            anchors.destination(currentWindows: []) == .leftOf(
                anchorFrame: temporaryMoveMainDivider.frame,
                anchorWindowID: nil
            )
        )
    }

    @Test
    func moveDestinationRequiresTheCorrectSideWithinTolerance() {
        let anchor = CGRect(x: 1_000, y: 0, width: 20, height: 24)
        let leftDestination = MenuBarItemMoveDestination.leftOf(
            anchorFrame: anchor,
            anchorWindowID: 1
        )
        let rightDestination = MenuBarItemMoveDestination.rightOf(
            anchorFrame: anchor,
            anchorWindowID: 1
        )

        #expect(leftDestination.isSatisfied(
            by: CGRect(x: 970, y: 0, width: 20, height: 24),
            tolerance: 25
        ))
        #expect(!leftDestination.isSatisfied(
            by: CGRect(x: 1_010, y: 0, width: 20, height: 24),
            tolerance: 300
        ))
        #expect(!leftDestination.isSatisfied(
            by: CGRect(x: 900, y: 0, width: 20, height: 24),
            tolerance: 25
        ))
        #expect(leftDestination.isSatisfied(
            by: CGRect(x: 988, y: 0, width: 20, height: 24),
            tolerance: 25
        ))
        #expect(!leftDestination.isSatisfied(
            by: CGRect(x: 989, y: 0, width: 20, height: 24),
            tolerance: 25
        ))

        #expect(rightDestination.isSatisfied(
            by: CGRect(x: 1_030, y: 0, width: 20, height: 24),
            tolerance: 25
        ))
        #expect(!rightDestination.isSatisfied(
            by: CGRect(x: 990, y: 0, width: 20, height: 24),
            tolerance: 300
        ))
        #expect(!rightDestination.isSatisfied(
            by: CGRect(x: 1_100, y: 0, width: 20, height: 24),
            tolerance: 25
        ))
        #expect(rightDestination.isSatisfied(
            by: CGRect(x: 1_012, y: 0, width: 20, height: 24),
            tolerance: 25
        ))
        #expect(!rightDestination.isSatisfied(
            by: CGRect(x: 1_011, y: 0, width: 20, height: 24),
            tolerance: 25
        ))
    }
}

@MainActor
private let temporaryMoveMainDivider = clickWindow(
    id: 900,
    frame: CGRect(x: -40, y: 0, width: 20, height: 24),
    ownerPID: 999
)

@MainActor
private let temporaryMoveToggle = clickWindow(
    id: 901,
    frame: CGRect(x: 300, y: 0, width: 24, height: 24),
    ownerPID: 999
)

@MainActor
private let temporaryMoveRightNeighbor = clickWindow(
    id: 43,
    frame: CGRect(x: -70, y: 0, width: 20, height: 24),
    ownerPID: 456
)

@MainActor
private let temporaryMoveItem = clickItem(
    id: 42,
    frame: CGRect(x: -100, y: 0, width: 20, height: 24)
)

@MainActor
private let temporaryMoveVisibleTarget = clickWindow(
    id: 42,
    frame: CGRect(x: 250, y: 0, width: 20, height: 24)
)

@MainActor
private let temporaryMoveInitialWindows = [
    clickWindow(
        id: 42,
        frame: CGRect(x: -100, y: 0, width: 20, height: 24)
    ),
    temporaryMoveRightNeighbor,
]

@MainActor
private let temporaryMoveVisibleWindows = [
    temporaryMoveRightNeighbor,
    temporaryMoveVisibleTarget,
]
