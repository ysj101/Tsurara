import CoreGraphics
import Foundation

public struct MenuBarItemPlacement: Equatable, Sendable {
    public let window: MenuBarItemWindow
    public let section: MenuBarSectionKind

    public init(window: MenuBarItemWindow, section: MenuBarSectionKind) {
        self.window = window
        self.section = section
    }
}

public enum MenuBarItemPlacementError: Error, LocalizedError {
    case unsupportedSection
    case alreadyMoving
    case subBarBusy
    case notMoved(underlying: any Error)
    case indeterminate(underlying: any Error)
    case mainDividerUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupportedSection: "常時非表示セクションの項目は移動できません。"
        case .alreadyMoving: "別のアイコンを移動中です。"
        case .subBarBusy: "サブバーの操作が終わるまでお待ちください。"
        case .notMoved: "アイコンを移動できませんでした。"
        case .indeterminate: "移動結果を確認できませんでした。メニューバーの配置を確認してください。"
        case .mainDividerUnavailable: "メイン区切りの位置を取得できませんでした。"
        }
    }
}

@MainActor
public final class MenuBarItemPlacementController {
    public static let pinnedSystemItemTitles: Set<String> = ["Clock", "BentoBox", "Siri"]

    private let windowLister: any MenuBarItemWindowListing
    private let mover: any MenuBarItemMoving
    private let repositionWaiter: MenuBarItemRepositionWaiter
    private var isMoving = false

    public init(
        windowLister: any MenuBarItemWindowListing,
        mover: any MenuBarItemMoving,
        pollInterval: Duration = .milliseconds(20),
        pollLimit: Int = 25
    ) {
        self.windowLister = windowLister
        self.mover = mover
        repositionWaiter = MenuBarItemRepositionWaiter(
            windowLister: windowLister,
            pollInterval: pollInterval,
            pollLimit: pollLimit
        )
    }

    public func listPlacements(
        mainDividerFrame: CGRect,
        subDividerFrame: CGRect?,
        displayFrames: [CGRect],
        excludedFrames: [CGRect],
        excludedTitles: Set<String>
    ) throws -> [MenuBarItemPlacement] {
        let windows = try windowLister.listMenuBarItemWindows()
        return windows.compactMap { window in
            guard !Self.pinnedSystemItemTitles.contains(window.title ?? ""),
                  !excludedTitles.contains(window.title ?? ""),
                  !excludedFrames.contains(where: { $0.contains(window.frame.center) }) else {
                return nil
            }
            guard let section = MenuBarItemSectionGeometry.section(
                of: window,
                mainDividerFrame: mainDividerFrame,
                subDividerFrame: subDividerFrame,
                displayFrames: displayFrames
            ), section != .alwaysHidden else {
                // 常時非表示項目はこの画面から移動できないため一覧に出さない。
                return nil
            }
            return MenuBarItemPlacement(window: window, section: section)
        }
        .sorted { lhs, rhs in
            if lhs.section != rhs.section {
                return lhs.section == .visible
            }
            return MenuBarItemWindow.isOrderedBefore(lhs.window, rhs.window)
        }
    }

    public func move(
        _ window: MenuBarItemWindow,
        to section: MenuBarSectionKind,
        mainDividerFrame: @escaping () -> CGRect?,
        subDividerFrame: CGRect? = nil,
        displayFrames: [CGRect] = []
    ) async throws -> MenuBarItemPlacement {
        guard !isMoving else { throw MenuBarItemPlacementError.alreadyMoving }
        let destination: MenuBarItemMoveDestination
        switch section {
        case .hidden:
            guard let frame = mainDividerFrame() else {
                throw MenuBarItemPlacementError.mainDividerUnavailable
            }
            destination = .leftOf(anchorFrame: frame, anchorWindowID: nil)
        case .visible:
            guard let frame = mainDividerFrame() else {
                throw MenuBarItemPlacementError.mainDividerUnavailable
            }
            destination = .rightOf(anchorFrame: frame, anchorWindowID: nil)
        case .alwaysHidden:
            throw MenuBarItemPlacementError.unsupportedSection
        }
        isMoving = true
        defer { isMoving = false }
        let movedWindow: MenuBarItemWindow
        do {
            movedWindow = try await mover.move(window, to: destination)
        } catch {
            switch error {
            case let .notMoved(underlying):
                throw MenuBarItemPlacementError.notMoved(underlying: underlying)
            case let .indeterminate(underlying):
                throw MenuBarItemPlacementError.indeterminate(underlying: underlying)
            }
        }
        // mover の到着判定は投稿前の区切り座標に対する緩い距離判定なので、一覧が
        // 使う厳密な分類に揃うまで有界時間だけ待つ。待ちきれなくても移動自体は
        // 成立しているため、列挙のばらつきを失敗として報告しない。
        let settled = try? await repositionWaiter.waitUntilReady(
            resolvingWindow: { windows in
                windows.first { $0.windowID == movedWindow.windowID }
            },
            isReady: { current in
                guard let dividerFrame = mainDividerFrame() else { return true }
                return MenuBarItemSectionGeometry.section(
                    of: current,
                    mainDividerFrame: dividerFrame,
                    subDividerFrame: subDividerFrame,
                    displayFrames: displayFrames
                ) == section
            }
        )
        return MenuBarItemPlacement(window: settled ?? movedWindow, section: section)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
