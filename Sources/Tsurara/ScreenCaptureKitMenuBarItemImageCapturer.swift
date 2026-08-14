import CoreGraphics
import ScreenCaptureKit
import TsuraraCore

/// ScreenCaptureKit の desktop-independent window capture を使う撮像実装。
@MainActor
final class ScreenCaptureKitMenuBarItemImageCapturer: MenuBarItemImageCapturing {
    func verifyScreenRecordingPermission() throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw MenuBarItemImagingError.screenRecordingPermissionDenied
        }
    }

    func capture(windowIDs: [CGWindowID]) async throws -> [CGWindowID: CGImage] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            let windowsByID = Dictionary(
                content.windows.map { ($0.windowID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var images: [CGWindowID: CGImage] = [:]
            for windowID in windowIDs {
                try Task.checkCancellation()
                guard let window = windowsByID[windowID] else { continue }
                do {
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let information = SCShareableContent.info(for: filter)
                    let configuration = SCStreamConfiguration()
                    configuration.width = max(
                        1,
                        Int(ceil(information.contentRect.width * CGFloat(information.pointPixelScale)))
                    )
                    configuration.height = max(
                        1,
                        Int(ceil(information.contentRect.height * CGFloat(information.pointPixelScale)))
                    )
                    configuration.captureResolution = .best
                    configuration.showsCursor = false
                    configuration.ignoreShadowsSingleWindow = true

                    images[windowID] = try await SCScreenshotManager.captureImage(
                        contentFilter: filter,
                        configuration: configuration
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let nsError = error as NSError
                    if nsError.domain == SCStreamErrorDomain, nsError.code == -3801 {
                        throw MenuBarItemImagingError.screenRecordingPermissionDenied
                    }
                    // 1 件の撮像失敗で、ほかの正常な項目を破棄しない。
                    continue
                }
            }
            return images
        } catch {
            // preflight 後にシステム設定が変わる競合でも、呼び出し側が同じ専用
            // エラーとして扱えるよう ScreenCaptureKit の拒否コードを正規化する。
            let nsError = error as NSError
            if nsError.domain == SCStreamErrorDomain, nsError.code == -3801 {
                throw MenuBarItemImagingError.screenRecordingPermissionDenied
            }
            throw error
        }
    }
}
