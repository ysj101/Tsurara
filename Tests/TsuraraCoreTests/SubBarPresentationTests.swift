import CoreGraphics
import Testing
import TsuraraCore

@MainActor
private final class MockSubBarPanelPresenter: SubBarPanelPresenting {
    private(set) var presentedAnchors: [CGRect] = []
    private(set) var presentedItemCounts: [Int] = []
    private(set) var dismissCount = 0
    var presentationSucceeds = true

    func present(
        items: [ImagedMenuBarItem],
        anchorFrame: @escaping @MainActor () -> CGRect?
    ) -> Bool {
        guard presentationSucceeds, let anchorFrame = anchorFrame() else { return false }
        presentedAnchors.append(anchorFrame)
        presentedItemCounts.append(items.count)
        return true
    }

    func dismiss() {
        dismissCount += 1
    }
}

@Suite
@MainActor
struct SubBarPresentationControllerTests {
    private func beginOpening(
        _ controller: SubBarPresentationController
    ) -> SubBarPresentationController.Generation {
        guard case let .beginOpening(generation) = controller.toggle() else {
            Issue.record("closed 状態から opening を開始できませんでした")
            return 0
        }
        return generation
    }

    @Test
    func toggleBeginsOpeningAndOpenPresentsThroughProtocol() {
        let presenter = MockSubBarPanelPresenter()
        let controller = SubBarPresentationController(presenter: presenter)
        let anchor = CGRect(x: 100, y: 800, width: 24, height: 24)

        #expect(controller.state == .closed)
        let generation = beginOpening(controller)
        #expect(controller.state == .opening)
        #expect(presenter.presentedItemCounts.isEmpty)

        controller.open(
            items: [],
            generation: generation,
            anchorFrame: { anchor }
        )

        #expect(controller.state == .open)
        #expect(presenter.presentedItemCounts == [0])
        #expect(presenter.presentedAnchors == [anchor])
    }

    @Test
    func togglingOpenPanelClosesItThroughProtocol() {
        let presenter = MockSubBarPanelPresenter()
        let controller = SubBarPresentationController(presenter: presenter)
        let generation = beginOpening(controller)
        controller.open(items: [], generation: generation, anchorFrame: { .zero })

        #expect(controller.toggle() == .close)

        #expect(controller.state == .closed)
        #expect(presenter.dismissCount == 1)
    }

    @Test
    func togglingDuringCaptureCancelsOpeningWithoutDismissingAbsentPanel() {
        let presenter = MockSubBarPanelPresenter()
        let controller = SubBarPresentationController(presenter: presenter)

        _ = beginOpening(controller)
        #expect(controller.toggle() == .close)

        #expect(controller.state == .closed)
        #expect(presenter.presentedItemCounts.isEmpty)
        #expect(presenter.dismissCount == 0)
    }

    @Test
    func repeatedOpenAndCloseCallsAreIdempotent() {
        let presenter = MockSubBarPanelPresenter()
        let controller = SubBarPresentationController(presenter: presenter)

        let generation = beginOpening(controller)
        controller.open(items: [], generation: generation, anchorFrame: { .zero })
        controller.open(items: [], generation: generation, anchorFrame: { .zero })
        controller.close()
        controller.close()

        #expect(presenter.presentedItemCounts == [0])
        #expect(presenter.dismissCount == 1)
        #expect(controller.state == .closed)
    }

    @Test
    func failedPresentationReturnsOpeningCycleToClosed() {
        let presenter = MockSubBarPanelPresenter()
        presenter.presentationSucceeds = false
        let controller = SubBarPresentationController(presenter: presenter)
        let generation = beginOpening(controller)

        let didOpen = controller.open(
            items: [],
            generation: generation,
            anchorFrame: { .zero }
        )

        #expect(!didOpen)
        #expect(controller.state == .closed)
        #expect(presenter.presentedItemCounts.isEmpty)
    }

    @Test
    func staleGenerationCannotCloseOrPresentNewCycle() {
        let presenter = MockSubBarPanelPresenter()
        let controller = SubBarPresentationController(presenter: presenter)
        let staleGeneration = beginOpening(controller)
        controller.close()
        let currentGeneration = beginOpening(controller)

        #expect(!controller.close(generation: staleGeneration))
        let staleDidOpen = controller.open(
            items: [],
            generation: staleGeneration,
            anchorFrame: { .zero }
        )
        #expect(!staleDidOpen)
        #expect(controller.state == .opening)
        #expect(controller.ownsCycle(currentGeneration))
    }

    @Test
    func staleGenerationCannotReleaseCurrentCaptureOwnership() {
        let presenter = MockSubBarPanelPresenter()
        let controller = SubBarPresentationController(presenter: presenter)
        let staleGeneration = beginOpening(controller)
        controller.close()
        let currentGeneration = beginOpening(controller)

        #expect(!controller.isLatestGeneration(staleGeneration))
        #expect(controller.isLatestGeneration(currentGeneration))
    }

    @Test
    func allOpeningExitPathsCanReturnStateToClosed() {
        let presenter = MockSubBarPanelPresenter()
        let controller = SubBarPresentationController(presenter: presenter)

        let missingDividerGeneration = beginOpening(controller)
        #expect(controller.close(generation: missingDividerGeneration))
        #expect(controller.state == .closed)

        let missingAnchorGeneration = beginOpening(controller)
        let missingAnchorDidOpen = controller.open(
            items: [],
            generation: missingAnchorGeneration,
            anchorFrame: { nil }
        )
        #expect(!missingAnchorDidOpen)
        #expect(controller.state == .closed)

        let errorGeneration = beginOpening(controller)
        #expect(controller.close(generation: errorGeneration))
        #expect(controller.state == .closed)
    }
}

@Suite
struct SubBarPanelLayoutCalculatorTests {
    private let calculator = SubBarPanelLayoutCalculator()

    @Test
    func centersPanelImmediatelyBelowAnchor() {
        let screen = SubBarScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )

        let frame = calculator.panelFrame(
            anchorFrame: CGRect(x: 700, y: 875, width: 20, height: 25),
            desiredSize: CGSize(width: 200, height: 40),
            screens: [screen]
        )

        #expect(frame == CGRect(x: 610, y: 835, width: 200, height: 40))
    }

    @Test
    func clampsPanelAtRightEdge() {
        let screen = SubBarScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )

        let frame = calculator.panelFrame(
            anchorFrame: CGRect(x: 1_420, y: 875, width: 20, height: 25),
            desiredSize: CGSize(width: 200, height: 40),
            screens: [screen]
        )

        #expect(frame?.maxX == 1_440)
        #expect(frame?.minX == 1_240)
    }

    @Test
    func usesDisplayContainingAnchorInMultiDisplayLayout() {
        let primary = SubBarScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let leftDisplay = SubBarScreenGeometry(
            frame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_055)
        )

        let frame = calculator.panelFrame(
            anchorFrame: CGRect(x: -40, y: 1_055, width: 24, height: 25),
            desiredSize: CGSize(width: 240, height: 40),
            screens: [primary, leftDisplay]
        )

        #expect(frame?.maxX == 0)
        #expect(frame?.minY == 1_015)
    }

    @Test
    func keepsPanelBelowNotchedMenuBarVisibleBoundary() {
        let notchedScreen = SubBarScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 944)
        )

        let frame = calculator.panelFrame(
            anchorFrame: CGRect(x: 700, y: 950, width: 24, height: 32),
            desiredSize: CGSize(width: 220, height: 40),
            screens: [notchedScreen]
        )

        #expect(frame?.maxY == notchedScreen.visibleFrame.maxY)
        #expect(frame?.minY == 904)
    }

    @Test
    func limitsOversizedPanelToVisibleScreen() {
        let screen = SubBarScreenGeometry(
            frame: CGRect(x: 100, y: 50, width: 800, height: 600),
            visibleFrame: CGRect(x: 100, y: 70, width: 800, height: 555)
        )

        let frame = calculator.panelFrame(
            anchorFrame: CGRect(x: 850, y: 625, width: 20, height: 25),
            desiredSize: CGSize(width: 1_200, height: 900),
            screens: [screen]
        )

        #expect(frame == screen.visibleFrame)
    }

    @Test
    func returnsNilWithoutScreens() {
        #expect(
            calculator.panelFrame(
                anchorFrame: .zero,
                desiredSize: CGSize(width: 100, height: 40),
                screens: []
            ) == nil
        )
    }
}
