import CoreGraphics
import Foundation
import Testing
import TsuraraCore

@MainActor
private final class StubMenuBarWindowLister: MenuBarItemWindowListing {
    var snapshots: [[MenuBarItemWindow]]
    private(set) var callCount = 0

    init(_ snapshots: [[MenuBarItemWindow]]) {
        self.snapshots = snapshots
    }

    func listMenuBarItemWindows() throws -> [MenuBarItemWindow] {
        defer { callCount += 1 }
        return snapshots[min(callCount, snapshots.count - 1)]
    }
}

@MainActor
private final class StubMenuBarImageCapturer: MenuBarItemImageCapturing {
    var permissionError: Error?
    var captureError: Error?
    private(set) var capturedWindowIDs: [CGWindowID] = []

    func verifyScreenRecordingPermission() throws {
        if let permissionError { throw permissionError }
    }

    func capture(windowID: CGWindowID) async throws -> CGImage {
        capturedWindowIDs.append(windowID)
        if let captureError { throw captureError }
        return CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data([0, 0, 0, 0]) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}

@MainActor
private final class StubCapturePositioner: MenuBarItemCapturePositioning {
    var needsRepositioning = false
    private(set) var preparedWindows: [MenuBarItemWindow] = []
    private(set) var restoreCallCount = 0

    func prepareForCapture(of windows: [MenuBarItemWindow]) async -> Bool {
        preparedWindows = windows
        return needsRepositioning
    }

    func restoreAfterCapture() {
        restoreCallCount += 1
    }
}

private func window(
    _ id: CGWindowID,
    x: CGFloat,
    y: CGFloat = 0,
    width: CGFloat = 20,
    ownerPID: pid_t = 100,
    ownerName: String = "Sample"
) -> MenuBarItemWindow {
    MenuBarItemWindow(
        windowID: id,
        frame: CGRect(x: x, y: y, width: width, height: 24),
        ownerPID: ownerPID,
        ownerName: ownerName
    )
}

@MainActor
@Suite
struct MenuBarItemImagingTests {
    @Test
    func capturesOnlyItemsBetweenSubAndMainDividersInVisualOrder() async throws {
        let windows = [
            window(90, x: -260, ownerName: "Always Hidden"),
            window(2, x: -200, width: 100), // サブ区切り
            window(12, x: -80, ownerName: "Left Item"),
            window(11, x: -50, ownerName: "Right Item"),
            window(1, x: -20, width: 200), // メイン区切り
            window(91, x: 190, ownerName: "Visible")
        ]
        let lister = StubMenuBarWindowLister([windows])
        let capturer = StubMenuBarImageCapturer()
        let imager = MenuBarItemImager(windowLister: lister, imageCapturer: capturer)

        let images = try await imager.captureHiddenItems(
            mainDividerWindowID: 1,
            subDividerWindowID: 2
        )

        #expect(images.map(\.windowID) == [12, 11])
        #expect(images.map(\.order) == [0, 1])
        #expect(images.map(\.owner.name) == ["Left Item", "Right Item"])
        #expect(images.map(\.owner.processIdentifier) == [100, 100])
        #expect(images.map(\.frame.minX) == [-80, -50])
        #expect(capturer.capturedWindowIDs == [12, 11])
    }

    @Test
    func capturesEverythingLeftOfMainDividerWhenSubDividerIsDisabled() async throws {
        let windows = [window(20, x: 10), window(1, x: 40), window(21, x: 80)]
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([windows]),
            imageCapturer: StubMenuBarImageCapturer()
        )

        let images = try await imager.captureHiddenItems(
            mainDividerWindowID: 1,
            subDividerWindowID: nil
        )

        #expect(images.map(\.windowID) == [20])
    }

    @Test
    func excludesWindowsOnAnotherMenuBarRow() async throws {
        let windows = [
            window(10, x: 10, y: 0),
            window(20, x: 10, y: 900),
            window(1, x: 40, y: 0)
        ]
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([windows]),
            imageCapturer: StubMenuBarImageCapturer()
        )

        let images = try await imager.captureHiddenItems(
            mainDividerWindowID: 1,
            subDividerWindowID: nil
        )

        #expect(images.map(\.windowID) == [10])
    }

    @Test
    func relistsWindowsAfterTemporarilyReturningOffscreenItems() async throws {
        let collapsed = [window(10, x: -100), window(1, x: -70, width: 100)]
        let exposed = [window(10, x: 500), window(1, x: 530)]
        let lister = StubMenuBarWindowLister([collapsed, exposed])
        let capturer = StubMenuBarImageCapturer()
        let positioner = StubCapturePositioner()
        positioner.needsRepositioning = true
        let imager = MenuBarItemImager(
            windowLister: lister,
            imageCapturer: capturer,
            capturePositioner: positioner
        )

        let images = try await imager.captureHiddenItems(
            mainDividerWindowID: 1,
            subDividerWindowID: nil
        )

        #expect(lister.callCount == 2)
        #expect(images.map(\.frame.minX) == [500])
        #expect(positioner.preparedWindows.map(\.windowID) == [10])
        #expect(positioner.restoreCallCount == 1)
    }

    @Test
    func restoresDividerWhenCaptureAfterRepositioningFails() async {
        struct CaptureFailure: Error {}

        let windows = [window(10, x: -100), window(1, x: -70, width: 100)]
        let capturer = StubMenuBarImageCapturer()
        capturer.captureError = CaptureFailure()
        let positioner = StubCapturePositioner()
        positioner.needsRepositioning = true
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([windows, windows]),
            imageCapturer: capturer,
            capturePositioner: positioner
        )

        await #expect(throws: CaptureFailure.self) {
            try await imager.captureHiddenItems(
                mainDividerWindowID: 1,
                subDividerWindowID: nil
            )
        }

        #expect(positioner.restoreCallCount == 1)
    }

    @Test
    func reportsDedicatedErrorWhenScreenRecordingIsNotAllowed() async {
        let capturer = StubMenuBarImageCapturer()
        capturer.permissionError = MenuBarItemImagingError.screenRecordingPermissionDenied
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([[window(1, x: 20)]]),
            imageCapturer: capturer
        )

        await #expect(throws: MenuBarItemImagingError.screenRecordingPermissionDenied) {
            try await imager.captureHiddenItems(mainDividerWindowID: 1, subDividerWindowID: nil)
        }
    }

    @Test
    func reportsMissingDividerInsteadOfGuessingSectionBoundaries() async {
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([[window(10, x: 20)]]),
            imageCapturer: StubMenuBarImageCapturer()
        )

        await #expect(throws: MenuBarItemImagingError.dividerWindowNotFound(windowID: 1)) {
            try await imager.captureHiddenItems(mainDividerWindowID: 1, subDividerWindowID: nil)
        }
    }
}
