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
    var failedWindowIDs: Set<CGWindowID> = []
    private(set) var capturedWindowIDs: [CGWindowID] = []
    private(set) var captureCallCount = 0

    func verifyScreenRecordingPermission() throws {
        if let permissionError { throw permissionError }
    }

    func capture(windowIDs: [CGWindowID]) async throws -> [CGWindowID: CGImage] {
        captureCallCount += 1
        capturedWindowIDs.append(contentsOf: windowIDs)
        return Dictionary(
            windowIDs.compactMap { windowID in
                guard !failedWindowIDs.contains(windowID) else { return nil }
                return (windowID, Self.image())
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func image() -> CGImage {
        CGImage(
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
    var readyWindowIDs: Set<CGWindowID>?
    var readyFrameMinX: CGFloat?
    private(set) var preparedWindows: [MenuBarItemWindow] = []
    private(set) var restoreCallCount = 0

    func prepareForCapture(of windows: [MenuBarItemWindow]) -> Bool {
        preparedWindows = windows
        return needsRepositioning
    }

    func isReadyForCapture(_ window: MenuBarItemWindow) -> Bool {
        if let readyFrameMinX { return window.frame.minX >= readyFrameMinX }
        return readyWindowIDs?.contains(window.windowID) ?? true
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
    ownerName: String = "Sample",
    displayFrame: CGRect? = nil
) -> MenuBarItemWindow {
    MenuBarItemWindow(
        windowID: id,
        frame: CGRect(x: x, y: y, width: width, height: 24),
        owner: MenuBarItemOwner(processIdentifier: ownerPID, name: ownerName),
        displayFrame: displayFrame
    )
}

@MainActor
@Suite
struct MenuBarItemImagingTests {
    @Test
    func visibilityRequiresIntersectionWithActualMenuBarRow() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        #expect(window(10, x: 100, y: 0).isVisibleOnMenuBar(displayFrames: [display]))
        #expect(!window(11, x: 100, y: 500).isVisibleOnMenuBar(displayFrames: [display]))
        #expect(!window(12, x: -100, y: 0).isVisibleOnMenuBar(displayFrames: [display]))
    }

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
        #expect(capturer.captureCallCount == 1)
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
    func excludesWindowsOnDisplayPlacedLeftOfMainDisplay() async throws {
        let leftDisplay = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let mainDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let windows = [
            window(20, x: -30, displayFrame: leftDisplay),
            window(10, x: 10, displayFrame: mainDisplay),
            window(1, x: 40, displayFrame: mainDisplay)
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
    func pollsUntilRepositionedWindowAppearsOnScreen() async throws {
        let collapsed = [window(10, x: -100), window(1, x: -70, width: 100)]
        let moving = [window(10, x: -20), window(1, x: 530)]
        let exposed = [window(10, x: 500), window(1, x: 530)]
        let lister = StubMenuBarWindowLister([collapsed, moving, exposed])
        let positioner = StubCapturePositioner()
        positioner.needsRepositioning = true
        positioner.readyFrameMinX = 0
        let imager = MenuBarItemImager(
            windowLister: lister,
            imageCapturer: StubMenuBarImageCapturer(),
            capturePositioner: positioner,
            repositionPollInterval: .zero,
            repositionPollLimit: 3
        )

        let images = try await imager.captureHiddenItems(
            mainDividerWindowID: 1,
            subDividerWindowID: nil
        )

        #expect(lister.callCount == 3)
        #expect(images.map(\.frame.minX) == [500])
    }

    @Test
    func removesWindowsMissingFromRefreshedListAndToleratesDuplicateIDs() async throws {
        let initial = [
            window(10, x: -100), window(11, x: -80),
            window(1, x: -50, width: 100)
        ]
        let refreshed = [
            window(11, x: 400), window(11, x: 500), window(1, x: 530)
        ]
        let positioner = StubCapturePositioner()
        positioner.needsRepositioning = true
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([initial, refreshed]),
            imageCapturer: StubMenuBarImageCapturer(),
            capturePositioner: positioner
        )

        let images = try await imager.captureHiddenItems(
            mainDividerWindowID: 1,
            subDividerWindowID: nil
        )

        #expect(images.map(\.windowID) == [11])
        #expect(images.map(\.frame.minX) == [500])
    }

    @Test
    func cancellationStopsPollingAndRestoresPosition() async {
        let windows = [window(10, x: -100), window(1, x: -70, width: 100)]
        let lister = StubMenuBarWindowLister([windows])
        let positioner = StubCapturePositioner()
        positioner.needsRepositioning = true
        positioner.readyWindowIDs = []
        let imager = MenuBarItemImager(
            windowLister: lister,
            imageCapturer: StubMenuBarImageCapturer(),
            capturePositioner: positioner,
            repositionPollInterval: .seconds(10),
            repositionPollLimit: 2
        )
        let task = Task {
            try await imager.captureHiddenItems(
                mainDividerWindowID: 1,
                subDividerWindowID: nil
            )
        }
        while lister.callCount < 2 { await Task.yield() }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(positioner.restoreCallCount == 1)
    }

    @Test
    func rejectsConcurrentCapture() async {
        let windows = [window(10, x: -100), window(1, x: -70, width: 100)]
        let lister = StubMenuBarWindowLister([windows])
        let positioner = StubCapturePositioner()
        positioner.needsRepositioning = true
        positioner.readyWindowIDs = []
        let imager = MenuBarItemImager(
            windowLister: lister,
            imageCapturer: StubMenuBarImageCapturer(),
            capturePositioner: positioner,
            repositionPollInterval: .seconds(10),
            repositionPollLimit: 2
        )
        let first = Task {
            try await imager.captureHiddenItems(
                mainDividerWindowID: 1,
                subDividerWindowID: nil
            )
        }
        while lister.callCount < 2 { await Task.yield() }

        await #expect(throws: MenuBarItemImagingError.captureAlreadyInProgress) {
            try await imager.captureHiddenItems(
                mainDividerWindowID: 1,
                subDividerWindowID: nil
            )
        }
        first.cancel()
        _ = try? await first.value
    }

    @Test
    func restoresDividerWhenCaptureAfterRepositioningFails() async {
        let windows = [
            window(10, x: -100), window(11, x: -80),
            window(1, x: -50, width: 100)
        ]
        let capturer = StubMenuBarImageCapturer()
        capturer.failedWindowIDs = [10]
        let positioner = StubCapturePositioner()
        positioner.needsRepositioning = true
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([windows, windows]),
            imageCapturer: capturer,
            capturePositioner: positioner
        )

        let images = try? await imager.captureHiddenItems(
            mainDividerWindowID: 1,
            subDividerWindowID: nil
        )

        #expect(positioner.restoreCallCount == 1)
        #expect(images?.map(\.windowID) == [11])
        #expect(images?.map(\.order) == [0])
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
