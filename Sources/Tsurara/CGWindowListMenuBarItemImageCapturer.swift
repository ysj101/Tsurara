import AppKit
import CoreGraphics
import TsuraraCore

/// CGWindowList 系の撮像 API は非推奨だが、ScreenCaptureKit は画面外のメニューバー
/// 項目を撮れないため代替がない。jordanbaird/Ice も同じ理由でこの API を使い続けている。
/// プロトコル経由で呼ぶことで非推奨警告だけを抑止する。
private protocol WindowListImage {
    init?(
        windowListFromArrayScreenBounds: CGRect,
        windowArray: CFArray,
        imageOption: CGWindowImageOption
    )
}

private extension WindowListImage {
    static func windowListImage(
        from screenBounds: CGRect,
        windowArray: CFArray,
        imageOption: CGWindowImageOption
    ) -> Self? {
        Self(
            windowListFromArrayScreenBounds: screenBounds,
            windowArray: windowArray,
            imageOption: imageOption
        )
    }
}

extension CGImage: WindowListImage {}

/// 画面外へ押し出された項目も WindowServer 上の windowID から直接撮像する。
@MainActor
final class CGWindowListMenuBarItemImageCapturer: MenuBarItemImageCapturing {
    private let permission: any ScreenCapturePermissionManaging
    private let option: CGWindowImageOption = [
        .boundsIgnoreFraming,
        .bestResolution,
    ]

    init(
        permission: any ScreenCapturePermissionManaging =
            CoreGraphicsScreenCapturePermissionManager.shared
    ) {
        self.permission = permission
    }

    func verifyScreenRecordingPermission() throws {
        // 権限がない場合もデスクトップだけの画像が返り得るため、結果ではなく
        // preflight で拒否を判別する。
        guard permission.status == .authorized else {
            throw MenuBarItemImagingError.screenRecordingPermissionDenied
        }
    }

    func capture(
        _ windows: [MenuBarItemWindow]
    ) throws -> [CGWindowID: CGImage] {
        guard !windows.isEmpty else { return [:] }

        let union = windows.reduce(CGRect.null) { $0.union($1.frame) }
        let scale = backingScaleFactor(for: union)

        if let windowArray = windowIDArray(for: windows),
           let composite = CGImage.windowListImage(
               from: .null,
               windowArray: windowArray,
               imageOption: option
           ),
           composite.width == Int((union.width * scale).rounded()) {
            var images: [CGWindowID: CGImage] = [:]
            images.reserveCapacity(windows.count)
            for window in windows {
                let cropRect = CGRect(
                    x: (window.frame.minX - union.minX) * scale,
                    y: (window.frame.minY - union.minY) * scale,
                    width: window.frame.width * scale,
                    height: window.frame.height * scale
                )
                if let image = composite.cropping(to: cropRect) {
                    images[window.windowID] = image
                }
            }
            return images
        }

        // WindowServer が合成画像へ余白を加える環境では切り出し位置を保証できない。
        // Ice と同様に各 windowID の個別撮像へ落とし、失敗した項目だけを飛ばす。
        var images: [CGWindowID: CGImage] = [:]
        images.reserveCapacity(windows.count)
        for window in windows {
            if let array = windowIDArray(for: [window]),
               let image = CGImage.windowListImage(
                   from: .null,
                   windowArray: array,
                   imageOption: option
               ) {
                images[window.windowID] = image
            }
        }
        return images
    }

    /// この API は配列の要素を「ポインタ値へキャストした windowID」として読む。
    /// NSNumber を入れると CFNumber のアドレスが windowID として解釈されるため、
    /// Ice と同じく生のポインタ値で CFArray を組み立てる。
    private func windowIDArray(for windows: [MenuBarItemWindow]) -> CFArray? {
        let pointers = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(
            capacity: windows.count
        )
        // CFArrayCreate は callbacks が NULL ならポインタ値をそのまま複製するため、
        // 生成後にバッファを解放してよい。
        defer { pointers.deallocate() }
        for (index, window) in windows.enumerated() {
            pointers[index] = UnsafeRawPointer(bitPattern: UInt(window.windowID))
        }
        return CFArrayCreate(kCFAllocatorDefault, pointers, windows.count, nil)
    }

    /// 画面外へ押し出された項目の union はどの画面にも含まれないため、通常は
    /// 主画面の倍率へ落ちる。倍率がずれた場合は合成画像の幅検証で弾かれ、
    /// 倍率に依存しない個別撮像へフォールバックする。
    private func backingScaleFactor(for frame: CGRect) -> CGFloat {
        zip(NSScreen.screens, AppKitScreenGeometry.cgFrames)
            .first { _, screenFrame in screenFrame.intersects(frame) }?.0
            .backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
    }
}
