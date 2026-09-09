import CoreGraphics
import Testing
import TsuraraCore

@Suite(.serialized)
@MainActor
struct MenuBarItemPlacementTests {
    private final class Lister: MenuBarItemWindowListing {
        let snapshots: [[MenuBarItemWindow]]
        var error: Error?
        private var callCount = 0

        init(_ windows: [MenuBarItemWindow]) { snapshots = [windows] }
        init(snapshots: [[MenuBarItemWindow]]) { self.snapshots = snapshots }

        func listMenuBarItemWindows() throws -> [MenuBarItemWindow] {
            if let error { throw error }
            defer { callCount += 1 }
            return snapshots[min(callCount, snapshots.count - 1)]
        }
    }

    private final class Mover: MenuBarItemMoving {
        var destination: MenuBarItemMoveDestination?
        var failure: MenuBarItemMoveFailure?
        var returnedWindow: MenuBarItemWindow?
        var delay = Duration.zero

        func move(
            _ item: MenuBarItemWindow,
            to destination: MenuBarItemMoveDestination,
            in windows: [MenuBarItemWindow]?
        ) async throws(MenuBarItemMoveFailure) -> MenuBarItemWindow {
            self.destination = destination
            if delay != .zero { try? await Task.sleep(for: delay) }
            if let failure { throw failure }
            return returnedWindow ?? item
        }
    }

    private let display = CGRect(x: 0, y: 0, width: 1_000, height: 100)
    private let divider = CGRect(x: 500, y: 0, width: 20, height: 24)

    private func item(
        _ id: CGWindowID,
        x: CGFloat,
        y: CGFloat = 0,
        displayFrame: CGRect? = nil,
        title: String? = nil
    ) -> MenuBarItemWindow {
        MenuBarItemWindow(
            windowID: id,
            frame: CGRect(x: x, y: y, width: 20, height: 24),
            owner: .init(processIdentifier: 10, name: "App"),
            title: title,
            displayFrame: displayFrame ?? display
        )
    }

    private func controller(
        lister: Lister,
        mover: Mover
    ) -> MenuBarItemPlacementController {
        MenuBarItemPlacementController(
            windowLister: lister,
            mover: mover,
            pollInterval: .zero,
            pollLimit: 3
        )
    }

    @Test func listPlacementsFiltersWindowsAndSortsSections() throws {
        let windows = [
            item(1, x: 700), item(2, x: 650), item(3, x: 300), item(4, x: 100),
            item(5, x: 400, displayFrame: CGRect(x: 1_000, y: 0, width: 500, height: 100)),
            item(6, x: 450, y: 80), item(8, x: 600, title: "Tsurara.toggleItem"),
            item(9, x: 620, title: "Clock")
        ]
        let result = try controller(lister: Lister(windows), mover: Mover()).listPlacements(
            mainDividerFrame: divider,
            subDividerFrame: CGRect(x: 200, y: 0, width: 20, height: 24),
            displayFrames: [display],
            excludedFrames: [CGRect(x: 700, y: 0, width: 20, height: 24)],
            excludedTitles: ["Tsurara.toggleItem"]
        )
        #expect(result.map(\.window.windowID) == [2, 3])
        #expect(result.map(\.section) == [.visible, .hidden])
    }

    @Test func sectionReturnsNilForDividerOverlap() {
        let window = item(1, x: 505)
        #expect(MenuBarItemSectionGeometry.section(of: window, mainDividerFrame: divider, subDividerFrame: nil, displayFrames: [display]) == nil)
    }

    @Test func alwaysHiddenSectionIsClassifiedAndExcludedFromList() throws {
        let window = item(1, x: 100)
        let subDivider = CGRect(x: 200, y: 0, width: 20, height: 24)
        #expect(MenuBarItemSectionGeometry.section(of: window, mainDividerFrame: divider, subDividerFrame: subDivider, displayFrames: [display]) == .alwaysHidden)
        let result = try controller(lister: Lister([window]), mover: Mover()).listPlacements(mainDividerFrame: divider, subDividerFrame: subDivider, displayFrames: [display], excludedFrames: [], excludedTitles: [])
        #expect(result.isEmpty)
    }

    @Test func excludedFrameUsesItsCenterPoint() throws {
        let result = try controller(lister: Lister([item(1, x: 700), item(2, x: 730)]), mover: Mover()).listPlacements(mainDividerFrame: divider, subDividerFrame: nil, displayFrames: [display], excludedFrames: [CGRect(x: 704, y: 4, width: 12, height: 16)], excludedTitles: [])
        #expect(result.map(\.window.windowID) == [2])
        #expect(MenuBarItemPlacementController.pinnedSystemItemTitles.contains("Clock"))
    }

    @Test func moveUsesLeftDestinationForHidden() async throws {
        let mover = Mover()
        let window = item(1, x: 700)
        try await controller(lister: Lister([window]), mover: mover).move(window, to: .hidden, mainDividerFrame: { divider })
        #expect(mover.destination == .leftOf(anchorFrame: divider, anchorWindowID: nil))
    }

    @Test func moveUsesRightDestinationForVisible() async throws {
        let mover = Mover()
        let window = item(1, x: 300)
        try await controller(lister: Lister([window]), mover: mover).move(window, to: .visible, mainDividerFrame: { divider })
        #expect(mover.destination == .rightOf(anchorFrame: divider, anchorWindowID: nil))
    }

    @Test func moveWaitsUntilRequestedSectionIsObserved() async throws {
        let oldWindow = item(1, x: 700)
        let newWindow = item(1, x: 300)
        let placement = try await controller(lister: Lister(snapshots: [[oldWindow], [newWindow]]), mover: Mover()).move(oldWindow, to: .hidden, mainDividerFrame: { divider }, displayFrames: [display])
        #expect(placement.window.frame == newWindow.frame)
        #expect(placement.section == .hidden)
    }

    @Test func moveReturnsMoverWindowWhenSectionNeverSettles() async throws {
        let oldWindow = item(1, x: 700)
        let returnedWindow = item(1, x: 710)
        let mover = Mover()
        mover.returnedWindow = returnedWindow
        let placement = try await controller(lister: Lister([oldWindow]), mover: mover).move(oldWindow, to: .hidden, mainDividerFrame: { divider }, displayFrames: [display])
        #expect(placement.window == returnedWindow)
        #expect(placement.section == .hidden)
    }

    @Test func listingErrorAfterMoveDoesNotFailMove() async throws {
        let lister = Lister([item(1, x: 700)])
        lister.error = StubError()
        let placement = try await controller(lister: lister, mover: Mover()).move(item(1, x: 700), to: .hidden, mainDividerFrame: { divider })
        #expect(placement.section == .hidden)
    }

    @Test func nilDividerFramePreventsMove() async {
        for section in [MenuBarSectionKind.hidden, .visible] {
            let mover = Mover()
            do {
                _ = try await controller(lister: Lister([item(1, x: 700)]), mover: mover).move(item(1, x: 700), to: section, mainDividerFrame: { nil })
                Issue.record("区切り座標が nil なのに移動が成功しました")
            } catch MenuBarItemPlacementError.mainDividerUnavailable {
                #expect(mover.destination == nil)
            } catch { Issue.record("想定外のエラーです") }
        }
    }

    @Test func moveFailuresPreserveUnderlyingError() async {
        for failure in [MenuBarItemMoveFailure.notMoved(StubError()), .indeterminate(StubError())] {
            let mover = Mover()
            mover.failure = failure
            do {
                _ = try await controller(lister: Lister([item(1, x: 700)]), mover: mover).move(item(1, x: 700), to: .hidden, mainDividerFrame: { divider })
                Issue.record("移動が成功してしまいました")
            } catch let error as MenuBarItemPlacementError {
                switch (failure, error) {
                case (.notMoved, let .notMoved(underlying)):
                    #expect(underlying is StubError)
                case (.indeterminate, let .indeterminate(underlying)):
                    #expect(underlying is StubError)
                default:
                    Issue.record("失敗種別が一致しません")
                }
            } catch { Issue.record("想定外のエラーです") }
        }
    }

    @Test func concurrentMoveIsRejected() async throws {
        let mover = Mover()
        mover.delay = .milliseconds(100)
        let window = item(1, x: 300)
        let placementController = controller(lister: Lister([window]), mover: mover)
        let first = Task { @MainActor in
            try await placementController.move(window, to: .visible, mainDividerFrame: { divider })
        }
        try await Task.sleep(for: .milliseconds(10))
        do {
            _ = try await placementController.move(window, to: .hidden, mainDividerFrame: { divider })
            Issue.record("同時移動が成功してしまいました")
        } catch MenuBarItemPlacementError.alreadyMoving { }
        _ = try await first.value
    }

    private struct StubError: Error { }
}
