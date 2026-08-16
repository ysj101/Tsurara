import CoreGraphics
import Foundation

/// CGWindowList から得た、撮像前のメニューバー項目ウィンドウ。
public struct MenuBarItemWindow: Equatable, Sendable {
    public let windowID: CGWindowID
    public let frame: CGRect
    public let owner: MenuBarItemOwner
    /// CGWindow と同じ左上原点座標系で、このウィンドウが属する画面。
    public let displayFrame: CGRect?

    public init(
        windowID: CGWindowID,
        frame: CGRect,
        owner: MenuBarItemOwner,
        displayFrame: CGRect? = nil
    ) {
        self.windowID = windowID
        self.frame = frame
        self.owner = owner
        self.displayFrame = displayFrame
    }
}

public struct MenuBarItemOwner: Equatable, Sendable {
    public let processIdentifier: pid_t
    public let name: String

    public init(processIdentifier: pid_t, name: String) {
        self.processIdentifier = processIdentifier
        self.name = name
    }
}

public extension MenuBarItemWindow {
    /// CG 座標系の画面矩形を使い、実際のメニューバー行に見えているか判定する。
    func isVisibleOnMenuBar(displayFrames: [CGRect]) -> Bool {
        displayFrames.contains { display in
            let menuBarBand = CGRect(
                x: display.minX,
                y: display.minY,
                width: display.width,
                height: max(64, frame.height)
            )
            return frame.intersects(menuBarBand)
        }
    }
}

/// サブバーが表示に使う、撮像済みのメニューバー項目。
// CGImage は不変オブジェクトだが SDK 上 Sendable ではないため、値型に閉じ込めた上で
// unchecked とする。画像のピクセルバッファをこの API から変更する手段はない。
public struct ImagedMenuBarItem: @unchecked Sendable {
    public let windowID: CGWindowID
    public let image: CGImage
    /// セクション判定時（撮像用に一時展開する前）の CG グローバル座標。
    /// クリック転送時に同じ実項目を幾何的に再特定するため保持する。
    public let sourceFrame: CGRect
    public let frame: CGRect
    public let owner: MenuBarItemOwner
    /// メニューバーを左から右へ見たときの 0 始まりの順序。
    public let order: Int

    public init(
        windowID: CGWindowID,
        image: CGImage,
        frame: CGRect,
        sourceFrame: CGRect? = nil,
        owner: MenuBarItemOwner,
        order: Int
    ) {
        self.windowID = windowID
        self.image = image
        self.sourceFrame = sourceFrame ?? frame
        self.frame = frame
        self.owner = owner
        self.order = order
    }
}

public enum MenuBarItemImagingError: Error, Equatable, LocalizedError {
    /// ScreenCaptureKit を呼ぶ前の preflight で権限がないことを検出した。
    case screenRecordingPermissionDenied
    /// ScreenCaptureKit の共有可能コンテンツから対象ウィンドウを解決できなかった。
    case captureWindowNotFound(windowID: CGWindowID)
    /// 同じ Imager に対する撮像要求がすでに進行中。
    case captureAlreadyInProgress

    public var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            "画面収録の許可を確認できません。"
        case let .captureWindowNotFound(windowID):
            "撮像対象（ウィンドウID: \(windowID)）が見つかりません。"
        case .captureAlreadyInProgress:
            "別のメニューバー撮像が進行中です。"
        }
    }
}

public enum MenuBarItemWindowListingError: Error, Equatable {
    case windowListUnavailable
}

@MainActor
public protocol MenuBarItemWindowListing: AnyObject {
    func listMenuBarItemWindows() throws -> [MenuBarItemWindow]
}

@MainActor
public protocol MenuBarItemImageCapturing: AnyObject {
    func verifyScreenRecordingPermission() throws
    /// 共有可能コンテンツを一度だけ取得し、撮像できた ID の画像を返す。
    func capture(windowIDs: [CGWindowID]) async throws -> [CGWindowID: CGImage]
}

/// 画面外へ押し出された項目を撮像可能な位置へ一時的に戻す操作の抽象化。
@MainActor
public protocol MenuBarItemCapturePositioning: AnyObject {
    /// 一時展開の所有権を取得した場合に true を返す。true の場合、呼び出し側は
    /// 再列挙したうえで、処理終了時に restoreAfterCapture を必ず1回呼ぶ。
    func prepareForCapture(of windows: [MenuBarItemWindow]) -> Bool
    func isReadyForCapture(_ window: MenuBarItemWindow) -> Bool
    func restoreAfterCapture()
}

public extension MenuBarItemCapturePositioning {
    func isReadyForCapture(_ window: MenuBarItemWindow) -> Bool { true }
}

@MainActor
private final class NoopMenuBarItemCapturePositioner: MenuBarItemCapturePositioning {
    func prepareForCapture(of windows: [MenuBarItemWindow]) -> Bool { false }
    func restoreAfterCapture() {}
}

/// 区切りの画面座標を基準に非表示セクションを選び、撮像結果へ組み立てる。
@MainActor
public final class MenuBarItemImager {
    private let windowLister: any MenuBarItemWindowListing
    private let imageCapturer: any MenuBarItemImageCapturing
    private let capturePositioner: any MenuBarItemCapturePositioning
    private let repositionPollInterval: Duration
    private let repositionPollLimit: Int
    private var isCapturing = false

    public init(
        windowLister: any MenuBarItemWindowListing,
        imageCapturer: any MenuBarItemImageCapturing,
        capturePositioner: (any MenuBarItemCapturePositioning)? = nil,
        repositionPollInterval: Duration = .milliseconds(20),
        repositionPollLimit: Int = 25
    ) {
        self.windowLister = windowLister
        self.imageCapturer = imageCapturer
        self.capturePositioner = capturePositioner ?? NoopMenuBarItemCapturePositioner()
        self.repositionPollInterval = repositionPollInterval
        self.repositionPollLimit = max(1, repositionPollLimit)
    }

    public func captureHiddenItems(
        mainDividerFrame: CGRect,
        subDividerFrame: CGRect?,
        displayFrames: [CGRect]
    ) async throws -> [ImagedMenuBarItem] {
        guard !isCapturing else {
            throw MenuBarItemImagingError.captureAlreadyInProgress
        }
        isCapturing = true
        defer { isCapturing = false }

        // length を戻して画面を動かす前に権限を確認する。
        try imageCapturer.verifyScreenRecordingPermission()

        let initialWindows = try windowLister.listMenuBarItemWindows()
        var targets = MenuBarItemSectionGeometry.hiddenWindows(
            in: initialWindows,
            mainDividerFrame: mainDividerFrame,
            subDividerFrame: subDividerFrame,
            displayFrames: displayFrames
        )
        let sourceFramesByID = Dictionary(
            targets.map { ($0.windowID, $0.frame) },
            uniquingKeysWith: { first, _ in first }
        )

        let repositioned = capturePositioner.prepareForCapture(of: targets)
        defer {
            if repositioned {
                capturePositioner.restoreAfterCapture()
            }
        }

        if repositioned {
            targets = try await waitForRepositionedWindows(targets)
        }
        return try await capture(targets, sourceFramesByID: sourceFramesByID)
    }

    private func waitForRepositionedWindows(
        _ targets: [MenuBarItemWindow]
    ) async throws -> [MenuBarItemWindow] {
        var refreshed: [MenuBarItemWindow] = []
        for attempt in 0..<repositionPollLimit {
            try Task.checkCancellation()
            let refreshedByID = Dictionary(
                try windowLister.listMenuBarItemWindows().map { ($0.windowID, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            // 再列挙から消えたウィンドウは stale frame へフォールバックしない。
            refreshed = targets.compactMap { refreshedByID[$0.windowID] }
            if refreshed.allSatisfy(capturePositioner.isReadyForCapture) {
                return refreshed
            }
            if attempt + 1 < repositionPollLimit {
                try await Task.sleep(for: repositionPollInterval)
            }
        }
        // タイムアウト時も、準備できた項目は部分成功として撮像する。
        return refreshed.filter(capturePositioner.isReadyForCapture)
    }

    private func capture(
        _ windows: [MenuBarItemWindow],
        sourceFramesByID: [CGWindowID: CGRect]
    ) async throws -> [ImagedMenuBarItem] {
        let imagesByID = try await imageCapturer.capture(
            windowIDs: windows.map(\.windowID)
        )
        var results: [ImagedMenuBarItem] = []
        results.reserveCapacity(windows.count)
        for window in windows {
            guard let image = imagesByID[window.windowID] else { continue }
            results.append(
                ImagedMenuBarItem(
                    windowID: window.windowID,
                    image: image,
                    frame: window.frame,
                    sourceFrame: sourceFramesByID[window.windowID],
                    owner: window.owner,
                    order: results.count
                )
            )
        }
        return results
    }
}

/// macOS 26 で自プロセスの status-level window が列挙されなくても使えるよう、
/// 区切り自体の windowID ではなく AppKit から得た CG グローバル座標を境界にする。
enum MenuBarItemSectionGeometry {
    static func hiddenWindows(
        in windows: [MenuBarItemWindow],
        mainDividerFrame: CGRect,
        subDividerFrame: CGRect?,
        displayFrames: [CGRect]
    ) -> [MenuBarItemWindow] {
        let dividerDisplay = displayContainingDivider(
            mainDividerFrame,
            among: displayFrames
        )

        // 拡大した区切りは数千 pt 幅になるため center は元の境界を表さない。
        // 従来どおり、メイン区切りの左端とサブ区切りの右端を使う。
        return windows
            .filter { window in
                guard window.frame.maxY > mainDividerFrame.minY,
                      window.frame.minY < mainDividerFrame.maxY,
                      belongsToSameDisplay(window, dividerDisplay: dividerDisplay),
                      window.frame.maxX <= mainDividerFrame.minX
                else { return false }
                return subDividerFrame.map {
                    window.frame.minX >= $0.maxX
                } ?? true
            }
            .sorted {
                if $0.frame.minX == $1.frame.minX {
                    return $0.windowID < $1.windowID
                }
                return $0.frame.minX < $1.frame.minX
            }
    }

    private static func displayContainingDivider(
        _ divider: CGRect,
        among displayFrames: [CGRect]
    ) -> CGRect? {
        // status item の右端は length を広げてもメニューバー上の固定位置に残る。
        // 境界上の丸め誤差を避け、右端から半 pt 内側の点で所属画面を決める。
        let point = CGPoint(
            x: max(divider.minX, divider.maxX - 0.5),
            y: divider.midY
        )
        return displayFrames.first { $0.contains(point) }
    }

    private static func belongsToSameDisplay(
        _ window: MenuBarItemWindow,
        dividerDisplay: CGRect?
    ) -> Bool {
        guard let dividerDisplay else { return true }
        // どの画面とも交差しない項目は区切りの拡大で画面外へ押し出された対象。
        // 別画面に属すると判明した項目だけを除外する。
        return window.displayFrame.map { $0 == dividerDisplay } ?? true
    }
}
