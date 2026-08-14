import CoreGraphics
import Foundation

/// CGWindowList から得た、撮像前のメニューバー項目ウィンドウ。
public struct MenuBarItemWindow: Equatable, Sendable {
    public let windowID: CGWindowID
    public let frame: CGRect
    public let ownerPID: pid_t
    public let ownerName: String

    public init(
        windowID: CGWindowID,
        frame: CGRect,
        ownerPID: pid_t,
        ownerName: String
    ) {
        self.windowID = windowID
        self.frame = frame
        self.ownerPID = ownerPID
        self.ownerName = ownerName
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

/// サブバーが表示に使う、撮像済みのメニューバー項目。
// CGImage は不変オブジェクトだが SDK 上 Sendable ではないため、値型に閉じ込めた上で
// unchecked とする。画像のピクセルバッファをこの API から変更する手段はない。
public struct ImagedMenuBarItem: @unchecked Sendable {
    public let windowID: CGWindowID
    public let image: CGImage
    public let frame: CGRect
    public let owner: MenuBarItemOwner
    /// メニューバーを左から右へ見たときの 0 始まりの順序。
    public let order: Int

    public init(
        windowID: CGWindowID,
        image: CGImage,
        frame: CGRect,
        owner: MenuBarItemOwner,
        order: Int
    ) {
        self.windowID = windowID
        self.image = image
        self.frame = frame
        self.owner = owner
        self.order = order
    }
}

public enum MenuBarItemImagingError: Error, Equatable {
    /// ScreenCaptureKit を呼ぶ前の preflight で権限がないことを検出した。
    case screenRecordingPermissionDenied
    /// 区切りが列挙結果にない場合、誤ったアプリを撮像しないよう処理を中止する。
    case dividerWindowNotFound(windowID: CGWindowID)
    /// ScreenCaptureKit の共有可能コンテンツから対象ウィンドウを解決できなかった。
    case captureWindowNotFound(windowID: CGWindowID)
}

@MainActor
public protocol MenuBarItemWindowListing: AnyObject {
    func listMenuBarItemWindows() throws -> [MenuBarItemWindow]
}

@MainActor
public protocol MenuBarItemImageCapturing: AnyObject {
    func verifyScreenRecordingPermission() throws
    func capture(windowID: CGWindowID) async throws -> CGImage
}

/// 画面外へ押し出された項目を撮像可能な位置へ一時的に戻す操作の抽象化。
@MainActor
public protocol MenuBarItemCapturePositioning: AnyObject {
    /// 実際に位置を変えた場合だけ true を返す。true の場合、呼び出し側が再列挙する。
    func prepareForCapture(of windows: [MenuBarItemWindow]) async -> Bool
    func restoreAfterCapture()
}

@MainActor
private final class NoopMenuBarItemCapturePositioner: MenuBarItemCapturePositioning {
    func prepareForCapture(of windows: [MenuBarItemWindow]) async -> Bool { false }
    func restoreAfterCapture() {}
}

/// 区切りウィンドウを基準に非表示セクションを選び、撮像結果へ組み立てる。
@MainActor
public final class MenuBarItemImager {
    private let windowLister: any MenuBarItemWindowListing
    private let imageCapturer: any MenuBarItemImageCapturing
    private let capturePositioner: any MenuBarItemCapturePositioning

    public init(
        windowLister: any MenuBarItemWindowListing,
        imageCapturer: any MenuBarItemImageCapturing,
        capturePositioner: (any MenuBarItemCapturePositioning)? = nil
    ) {
        self.windowLister = windowLister
        self.imageCapturer = imageCapturer
        self.capturePositioner = capturePositioner ?? NoopMenuBarItemCapturePositioner()
    }

    public func captureHiddenItems(
        mainDividerWindowID: CGWindowID,
        subDividerWindowID: CGWindowID?
    ) async throws -> [ImagedMenuBarItem] {
        // length を戻して画面を動かす前に権限を確認する。
        try imageCapturer.verifyScreenRecordingPermission()

        let initialWindows = try windowLister.listMenuBarItemWindows()
        var targets = try hiddenWindows(
            in: initialWindows,
            mainDividerWindowID: mainDividerWindowID,
            subDividerWindowID: subDividerWindowID
        )

        let repositioned = await capturePositioner.prepareForCapture(of: targets)
        if repositioned {
            defer { capturePositioner.restoreAfterCapture() }
            let refreshedByID = Dictionary(
                uniqueKeysWithValues: try windowLister.listMenuBarItemWindows().map {
                    ($0.windowID, $0)
                }
            )
            targets = targets.map { refreshedByID[$0.windowID] ?? $0 }
            return try await capture(targets)
        }

        return try await capture(targets)
    }

    private func hiddenWindows(
        in windows: [MenuBarItemWindow],
        mainDividerWindowID: CGWindowID,
        subDividerWindowID: CGWindowID?
    ) throws -> [MenuBarItemWindow] {
        guard let mainDivider = windows.first(where: { $0.windowID == mainDividerWindowID })
        else {
            throw MenuBarItemImagingError.dividerWindowNotFound(
                windowID: mainDividerWindowID
            )
        }

        let subDivider: MenuBarItemWindow?
        if let subDividerWindowID {
            guard let found = windows.first(where: { $0.windowID == subDividerWindowID })
            else {
                throw MenuBarItemImagingError.dividerWindowNotFound(
                    windowID: subDividerWindowID
                )
            }
            subDivider = found
        } else {
            subDivider = nil
        }

        // 拡大した区切りのウィンドウ自体も数千 pt 幅になる。center では元の境界を
        // 表せないため、メイン区切りの左端とサブ区切りの右端を境界として使う。
        return windows
            .filter { window in
                guard window.windowID != mainDividerWindowID,
                      window.windowID != subDividerWindowID,
                      // 複数ディスプレイで同じ x 座標にある別メニューバーの
                      // ウィンドウを混ぜない。CGWindow の座標系の y 方向は
                      // NSScreen と異なるため、ここでは列挙結果同士だけを比較する。
                      window.frame.maxY > mainDivider.frame.minY,
                      window.frame.minY < mainDivider.frame.maxY,
                      window.frame.maxX <= mainDivider.frame.minX
                else { return false }
                return subDivider.map { window.frame.minX >= $0.frame.maxX } ?? true
            }
            .sorted {
                if $0.frame.minX == $1.frame.minX {
                    return $0.windowID < $1.windowID
                }
                return $0.frame.minX < $1.frame.minX
            }
    }

    private func capture(
        _ windows: [MenuBarItemWindow]
    ) async throws -> [ImagedMenuBarItem] {
        var results: [ImagedMenuBarItem] = []
        results.reserveCapacity(windows.count)
        for (order, window) in windows.enumerated() {
            let image = try await imageCapturer.capture(windowID: window.windowID)
            results.append(
                ImagedMenuBarItem(
                    windowID: window.windowID,
                    image: image,
                    frame: window.frame,
                    owner: MenuBarItemOwner(
                        processIdentifier: window.ownerPID,
                        name: window.ownerName
                    ),
                    order: order
                )
            )
        }
        return results
    }
}
