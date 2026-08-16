import CoreGraphics
import Testing
import TsuraraCore

@Suite
struct CGWindowCoordinateSpaceTests {
    @Test
    func convertsAppKitFrameByFlippingYAndPreservingSize() {
        let frame = CGWindowCoordinateSpace.frame(
            fromAppKit: CGRect(x: -120, y: 700, width: 24, height: 30),
            primaryMaxY: 1_080
        )

        #expect(frame == CGRect(x: -120, y: 350, width: 24, height: 30))
    }
}
