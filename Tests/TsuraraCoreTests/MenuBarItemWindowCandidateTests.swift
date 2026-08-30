import CoreGraphics
import Testing
import TsuraraCore

@Suite
struct MenuBarItemWindowCandidateTests {
    private let statusWindowLevel: Int32 = 25
    private let display = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)

    @Test
    func acceptsOffscreenItemAtStatusLevel() {
        #expect(isCandidate(layer: statusWindowLevel, x: -500, y: 500))
    }

    @Test(arguments: [Int32(26), Int32(27)])
    func acceptsItemNearStatusLevelInMenuBarBand(layer: Int32) {
        #expect(isCandidate(layer: layer, x: -100, y: 4))
    }

    @Test
    func rejectsDisplayWideMainMenuWindow() {
        let narrowDisplay = CGRect(x: 0, y: 0, width: 400, height: 800)
        #expect(!MenuBarItemWindowCandidate.isMenuBarItemWindow(
            layer: statusWindowLevel - 1,
            frame: CGRect(x: 0, y: 0, width: narrowDisplay.width, height: 24),
            statusWindowLevel: statusWindowLevel,
            displayFrames: [narrowDisplay]
        ))
    }

    @Test
    func rejectsNormalWindow() {
        #expect(!isCandidate(
            layer: 0,
            x: 100,
            y: 200,
            width: 800,
            height: 600
        ))
    }

    @Test
    func rejectsNearbyLevelOutsideMenuBarBand() {
        #expect(!isCandidate(layer: statusWindowLevel + 1, x: 100, y: 500))
    }

    @Test
    func rejectsHugeWindowAtNearbyLevel() {
        #expect(!isCandidate(
            layer: statusWindowLevel + 1,
            x: 0,
            y: 0,
            width: 1_000,
            height: 700
        ))
    }

    private func isCandidate(
        layer: Int32,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat = 24,
        height: CGFloat = 24
    ) -> Bool {
        MenuBarItemWindowCandidate.isMenuBarItemWindow(
            layer: layer,
            frame: CGRect(x: x, y: y, width: width, height: height),
            statusWindowLevel: statusWindowLevel,
            displayFrames: [display]
        )
    }
}
