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

    func capture(windowID: CGWindowID) async throws -> CGImage {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw MenuBarItemImagingError.captureWindowNotFound(windowID: windowID)
            }

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

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
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
