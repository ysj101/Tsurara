import CoreGraphics
import Foundation
import Testing
import TsuraraCore

@MainActor
private final class StubMenuBarWindowLister: MenuBarItemWindowListing {
    var windows: [MenuBarItemWindow]
    private(set) var callCount = 0

    init(_ windows: [MenuBarItemWindow]) {
        self.windows = windows
    }

    func listMenuBarItemWindows() throws -> [MenuBarItemWindow] {
        callCount += 1
        return windows
    }
}

@MainActor
private final class StubMenuBarImageCapturer: MenuBarItemImageCapturing {
    var permissionError: Error?
    var captureError: Error?
    var failedWindowIDs: Set<CGWindowID> = []
    private(set) var capturedWindows: [[MenuBarItemWindow]] = []

    func verifyScreenRecordingPermission() throws {
        if let permissionError { throw permissionError }
    }

    func capture(
        _ windows: [MenuBarItemWindow]
    ) throws -> [CGWindowID: CGImage] {
        capturedWindows.append(windows)
        if let captureError { throw captureError }
        return Dictionary(
            windows.compactMap { window in
                guard !failedWindowIDs.contains(window.windowID) else { return nil }
                return (window.windowID, Self.image())
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
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: CGDataProvider(data: Data([0, 0, 0, 0]) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
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

private let testDisplayFrames = [
    CGRect(x: -5_000, y: 0, width: 10_000, height: 1_080)
]

@MainActor
@Suite
struct MenuBarItemImagingTests {
    @Test
    func visibilityRequiresIntersectionWithActualMenuBarRow() {
        let display = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)

        #expect(window(10, x: 100, y: 0).isVisibleOnMenuBar(displayFrames: [display]))
        #expect(!window(11, x: 100, y: 500).isVisibleOnMenuBar(displayFrames: [display]))
        #expect(!window(12, x: -100, y: 0).isVisibleOnMenuBar(displayFrames: [display]))
    }

    @Test
    func capturesOnlyItemsBetweenSubAndMainDividersInVisualOrder() async throws {
        let windows = [
            window(90, x: -260, ownerName: "Always Hidden"),
            window(2, x: -200, width: 100),
            window(12, x: -80, ownerName: "Left Item"),
            window(11, x: -50, ownerName: "Right Item"),
            window(1, x: -20, width: 200),
            window(91, x: 190, ownerName: "Visible"),
        ]
        let lister = StubMenuBarWindowLister(windows)
        let capturer = StubMenuBarImageCapturer()
        let imager = MenuBarItemImager(windowLister: lister, imageCapturer: capturer)

        let images = try await imager.captureHiddenItems(
            mainDividerFrame: CGRect(x: -20, y: 0, width: 200, height: 24),
            subDividerFrame: CGRect(x: -200, y: 0, width: 100, height: 24),
            displayFrames: testDisplayFrames
        )

        #expect(images.map(\.windowID) == [12, 11])
        #expect(images.map(\.order) == [0, 1])
        #expect(images.map(\.owner.name) == ["Left Item", "Right Item"])
        #expect(images.map(\.frame.minX) == [-80, -50])
        #expect(images.map(\.sourceFrame.minX) == [-80, -50])
        #expect(capturer.capturedWindows.map { $0.map(\.windowID) } == [[12, 11]])
        #expect(lister.callCount == 1)
    }

    @Test
    func capturesOffscreenItemsWithoutRepositioningOrRelisting() async throws {
        let offscreen = window(10, x: -10_000, width: 24)
        let lister = StubMenuBarWindowLister([
            offscreen,
            window(1, x: -9_970, width: 10_000),
        ])
        let capturer = StubMenuBarImageCapturer()
        let imager = MenuBarItemImager(windowLister: lister, imageCapturer: capturer)

        let images = try await imager.captureHiddenItems(
            mainDividerFrame: CGRect(x: -9_970, y: 0, width: 10_000, height: 24),
            subDividerFrame: nil,
            displayFrames: testDisplayFrames
        )

        #expect(lister.callCount == 1)
        #expect(capturer.capturedWindows == [[offscreen]])
        #expect(images.map(\.windowID) == [10])
        #expect(images.first?.frame == offscreen.frame)
        #expect(images.first?.sourceFrame == offscreen.frame)
    }

    @Test
    func capturesEverythingLeftOfMainDividerWhenSubDividerIsDisabled() async throws {
        let capturer = StubMenuBarImageCapturer()
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([
                window(20, x: 10), window(1, x: 40), window(21, x: 80),
            ]),
            imageCapturer: capturer
        )

        let images = try await imager.captureHiddenItems(
            mainDividerFrame: CGRect(x: 40, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: testDisplayFrames
        )

        #expect(images.map(\.windowID) == [20])
    }

    @Test
    func excludesWindowsOnAnotherMenuBarRow() async throws {
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([
                window(10, x: 10, y: 0),
                window(20, x: 10, y: 900),
                window(1, x: 40, y: 0),
            ]),
            imageCapturer: StubMenuBarImageCapturer()
        )

        let images = try await imager.captureHiddenItems(
            mainDividerFrame: CGRect(x: 40, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: testDisplayFrames
        )

        #expect(images.map(\.windowID) == [10])
    }

    @Test
    func excludesWindowsOnAnotherDisplay() async throws {
        let leftDisplay = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let mainDisplay = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([
                window(20, x: -30, displayFrame: leftDisplay),
                window(10, x: 10, displayFrame: mainDisplay),
            ]),
            imageCapturer: StubMenuBarImageCapturer()
        )

        let images = try await imager.captureHiddenItems(
            mainDividerFrame: CGRect(x: 40, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: [leftDisplay, mainDisplay]
        )

        #expect(images.map(\.windowID) == [10])
    }

    @Test
    func dividerDoesNotNeedToExistInWindowList() async throws {
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([window(10, x: 20)]),
            imageCapturer: StubMenuBarImageCapturer()
        )

        let images = try await imager.captureHiddenItems(
            mainDividerFrame: CGRect(x: 40, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: testDisplayFrames
        )

        #expect(images.map(\.windowID) == [10])
    }

    @Test
    func excludesOtherDisplayWhenDividerDisplayHasNoListedStatusWindows() async throws {
        let leftDisplay = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let mainDisplay = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([
                window(20, x: -40, displayFrame: leftDisplay),
            ]),
            imageCapturer: StubMenuBarImageCapturer()
        )

        let images = try await imager.captureHiddenItems(
            mainDividerFrame: CGRect(x: 40, y: 0, width: 20, height: 24),
            subDividerFrame: nil,
            displayFrames: [leftDisplay, mainDisplay]
        )

        #expect(images.isEmpty)
    }

    @Test
    func toleratesIndividualCaptureFailures() async throws {
        let capturer = StubMenuBarImageCapturer()
        capturer.failedWindowIDs = [10]
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([
                window(10, x: -100),
                window(11, x: -80),
            ]),
            imageCapturer: capturer
        )

        let images = try await imager.captureHiddenItems(
            mainDividerFrame: CGRect(x: -50, y: 0, width: 100, height: 24),
            subDividerFrame: nil,
            displayFrames: testDisplayFrames
        )

        #expect(images.map(\.windowID) == [11])
        #expect(images.map(\.order) == [0])
        #expect(capturer.capturedWindows.first?.map(\.windowID) == [10, 11])
    }

    @Test
    func reportsDedicatedErrorWhenScreenRecordingIsNotAllowed() async {
        let capturer = StubMenuBarImageCapturer()
        capturer.permissionError = MenuBarItemImagingError.screenRecordingPermissionDenied
        let lister = StubMenuBarWindowLister([window(1, x: 20)])
        let imager = MenuBarItemImager(windowLister: lister, imageCapturer: capturer)

        await #expect(throws: MenuBarItemImagingError.screenRecordingPermissionDenied) {
            try await imager.captureHiddenItems(
                mainDividerFrame: CGRect(x: 20, y: 0, width: 20, height: 24),
                subDividerFrame: nil,
                displayFrames: testDisplayFrames
            )
        }

        #expect(lister.callCount == 0)
        #expect(capturer.capturedWindows.isEmpty)
    }

    @Test
    func rejectsConcurrentCapture() async {
        let imager = MenuBarItemImager(
            windowLister: StubMenuBarWindowLister([window(10, x: -100)]),
            imageCapturer: StubMenuBarImageCapturer()
        )
        let capture: @MainActor @Sendable () async -> Result<Void, Error> = {
            do {
                _ = try await imager.captureHiddenItems(
                    mainDividerFrame: CGRect(x: -50, y: 0, width: 20, height: 24),
                    subDividerFrame: nil,
                    displayFrames: testDisplayFrames
                )
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        let first = Task { await capture() }
        let second = Task { await capture() }
        let results = [await first.value, await second.value]
        let errors = results.compactMap { result -> Error? in
            guard case let .failure(error) = result else { return nil }
            return error
        }

        #expect(errors.count == 1)
        #expect(errors.first as? MenuBarItemImagingError == .captureAlreadyInProgress)
    }
}
