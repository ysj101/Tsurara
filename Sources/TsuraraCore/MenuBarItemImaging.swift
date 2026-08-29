import CoreGraphics
import Foundation

/// title の「空文字は情報なし」という規則を、生成元によらず 1 箇所で適用する。
private func normalizedTitle(_ title: String?) -> String? {
    title?.isEmpty == false ? title : nil
}

/// CGWindowList から得た、撮像前のメニューバー項目ウィンドウ。
public struct MenuBarItemWindow: Equatable, Sendable {
    public let windowID: CGWindowID
    public let frame: CGRect
    public let owner: MenuBarItemOwner
    public let title: String?
    /// CGWindow と同じ左上原点座標系で、このウィンドウが属する画面。
    public let displayFrame: CGRect?

    public init(
        windowID: CGWindowID,
        frame: CGRect,
        owner: MenuBarItemOwner,
        title: String? = nil,
        displayFrame: CGRect? = nil
    ) {
        self.windowID = windowID
        self.frame = frame
        self.owner = owner
        self.title = normalizedTitle(title)
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

    /// WindowServer の列挙順に依存せず、メニューバー上の左から右を決める。
    static func isOrderedBefore(
        _ lhs: MenuBarItemWindow,
        _ rhs: MenuBarItemWindow
    ) -> Bool {
        if lhs.frame.minX == rhs.frame.minX {
            return lhs.windowID < rhs.windowID
        }
        return lhs.frame.minX < rhs.frame.minX
    }
}

/// サブバーが表示に使う、撮像済みのメニューバー項目。
// CGImage は不変オブジェクトだが SDK 上 Sendable ではないため、値型に閉じ込めた上で
// unchecked とする。画像のピクセルバッファをこの API から変更する手段はない。
public struct ImagedMenuBarItem: @unchecked Sendable {
    public let windowID: CGWindowID
    public let image: CGImage
    /// 撮像対象を列挙した時点での、現在の実際の CG グローバル座標。
    /// クリック転送時に同じ実項目を幾何的に再特定するため保持する。
    public let sourceFrame: CGRect
    public let frame: CGRect
    public let owner: MenuBarItemOwner
    public let title: String?
    /// メニューバーを左から右へ見たときの 0 始まりの順序。
    public let order: Int

    public init(
        windowID: CGWindowID,
        image: CGImage,
        frame: CGRect,
        sourceFrame: CGRect? = nil,
        owner: MenuBarItemOwner,
        title: String? = nil,
        order: Int
    ) {
        self.windowID = windowID
        self.image = image
        self.sourceFrame = sourceFrame ?? frame
        self.frame = frame
        self.owner = owner
        self.title = normalizedTitle(title)
        self.order = order
    }
}

public enum MenuBarItemImagingError: Error, Equatable, LocalizedError {
    /// ウィンドウ撮像前の preflight で権限がないことを検出した。
    case screenRecordingPermissionDenied

    public var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            "画面収録の許可を確認できません。"
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
    /// 画面外の項目も含め、渡したウィンドウの画像を返す。撮れた ID だけを含む。
    func capture(_ windows: [MenuBarItemWindow]) throws -> [CGWindowID: CGImage]
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
struct MenuBarItemRepositionWaiter {
    private let windowLister: any MenuBarItemWindowListing
    private let pollInterval: Duration
    private let pollLimit: Int

    init(
        windowLister: any MenuBarItemWindowListing,
        pollInterval: Duration,
        pollLimit: Int
    ) {
        self.windowLister = windowLister
        self.pollInterval = pollInterval
        self.pollLimit = max(1, pollLimit)
    }

    func waitUntilReady(
        resolvingWindow resolve: ([MenuBarItemWindow]) -> MenuBarItemWindow?,
        isReady: (MenuBarItemWindow) -> Bool
    ) async throws -> MenuBarItemWindow? {
        for attempt in 0..<pollLimit {
            try Task.checkCancellation()
            // 再配置中は対象が一瞬だけ列挙から消えることがあるため、nil でも
            // タイムアウトまでは次の列挙を待つ。
            if let window = resolve(try windowLister.listMenuBarItemWindows()),
               isReady(window) {
                return window
            }
            if attempt + 1 < pollLimit {
                try await Task.sleep(for: pollInterval)
            }
        }
        return nil
    }
}

/// 区切りの画面座標を基準に非表示セクションを選び、撮像結果へ組み立てる。
@MainActor
public final class MenuBarItemImager {
    private let windowLister: any MenuBarItemWindowListing
    private let imageCapturer: any MenuBarItemImageCapturing

    public init(
        windowLister: any MenuBarItemWindowListing,
        imageCapturer: any MenuBarItemImageCapturing
    ) {
        self.windowLister = windowLister
        self.imageCapturer = imageCapturer
    }

    public func captureHiddenItems(
        mainDividerFrame: CGRect,
        subDividerFrame: CGRect?,
        displayFrames: [CGRect]
    ) async throws -> [ImagedMenuBarItem] {
        // 撮像が同期化され、本体に中断点がなくなったため、MainActor の直列化だけで
        // 撮像要求どうしは重ならない。async は呼び出し側の Task 構造を保つために残す。
        try imageCapturer.verifyScreenRecordingPermission()

        let windows = try windowLister.listMenuBarItemWindows()
        let targets = MenuBarItemSectionGeometry.hiddenWindows(
            in: windows,
            mainDividerFrame: mainDividerFrame,
            subDividerFrame: subDividerFrame,
            displayFrames: displayFrames
        )
        let imagesByID = try imageCapturer.capture(targets)
        var results: [ImagedMenuBarItem] = []
        results.reserveCapacity(targets.count)
        for window in targets {
            guard let image = imagesByID[window.windowID] else { continue }
            results.append(
                ImagedMenuBarItem(
                    windowID: window.windowID,
                    image: image,
                    frame: window.frame,
                    sourceFrame: window.frame,
                    owner: window.owner,
                    title: window.title,
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
            .sorted(by: MenuBarItemWindow.isOrderedBefore)
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
