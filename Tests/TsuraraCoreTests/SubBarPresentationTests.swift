import CoreGraphics
import Testing
import TsuraraCore

@MainActor
private final class MockSubBarPanelPresenter: SubBarPanelPresenting {
    private(set) var presentedAnchors: [CGRect] = []
    private(set) var presentedItemCounts: [Int] = []
    private(set) var dismissCount = 0

    func present(items: [ImagedMenuBarItem], anchorFrame: CGRect) {
        presentedAnchors.append(anchorFrame)
        presentedItemCounts.append(items.count)
    }

    func dismiss() {
        dismissCount += 1
    }
}

@Suite
@MainActor
struct SubBarPresentationControllerTests {
    @Test
    func toggleBeginsOpeningAndOpenPresentsThroughProtocol() {
        let presenter = MockSubBarPanelPresenter()
        let controller = SubBarPresentationController(presenter: presenter)
        let anchor = CGRect(x: 100, y: 800, width: 24, height: 24)

        #expect(controller.state == .closed)
        #expect(controller.toggle() == .beginOpening)
        #expect(controller.state == .opening)
        #expect(presenter.presentedItemCounts.isEmpty)

        controller.open(items: [], anchorFrame: anchor)

        #expect(controller.state == .open)
        #expect(controller.isOpen)
        #expect(presenter.presentedItemCounts == [0])
        #expect(presenter.presentedAnchors == [anchor])
    }

    @Test
    func togglingOpenPanelClosesItThroughProtocol() {
        let presenter = MockSubBarPanelPresenter()
        let controller = SubBarPresentationController(presenter: presenter)
        controller.open(items: [], anchorFrame: .zero)

        #expect(controller.toggle() == .close)

        #expect(controller.state == .closed)
        #expect(presenter.dismissCount == 1)
    }

    @Test
    func togglingDuringCaptureCancelsOpeningWithoutDismissingAbsentPanel() {
        let presenter = MockSubBarPanelPresenter()
        let controller = SubBarPresentationController(presenter: presenter)

        #expect(controller.toggle() == .beginOpening)
        #expect(controller.toggle() == .close)

        #expect(controller.state == .closed)
        #expect(presenter.presentedItemCounts.isEmpty)
        #expect(presenter.dismissCount == 0)
    }

    @Test
    func repeatedOpenAndCloseCallsAreIdempotent() {
        let presenter = MockSubBarPanelPresenter()
        let controller = SubBarPresentationController(presenter: presenter)

        controller.open(items: [], anchorFrame: .zero)
        controller.open(items: [], anchorFrame: .zero)
        controller.close()
        controller.close()

        #expect(presenter.presentedItemCounts == [0])
        #expect(presenter.dismissCount == 1)
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
