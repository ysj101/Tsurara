import AppKit
import CoreGraphics
import os
import ScreenCaptureKit
import TsuraraCore

/// 一時展開の直前に撮ったメニューバー領域を最前面へ重ね、撮像中の動きを隠す。
@MainActor
final class ScreenCaptureKitMenuBarAreaMasker: MenuBarCaptureAreaMasking {
    private let logger = Logger(subsystem: "com.ysj.Tsurara", category: "capture")
    // WindowServer が length 変更を反映するまでの猶予。実測に基づく経験値で、
    // 展開側は 20ms 間隔で最大 25 回待つ既存の再配置待ちも踏まえている。
    private let maskCommitDelay: Duration = .milliseconds(32)
    private let unmaskDelay: Duration = .milliseconds(150)
    private var panel: NSPanel?

    func beginMasking(area: CGRect) async -> Bool {
        // 前回のパネルが万一残っていても、古い画面構成の位置へ表示し続けない。
        endMasking()

        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else {
            logger.error("AppKit 座標へ変換するための主画面が見つかりません")
            return false
        }

        // 項目撮像用の共有可能コンテンツは、一時展開後の位置でウィンドウを
        // 解決する必要がある。展開前の帯を撮るこの列挙とは統合できない。
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            guard let display = content.displays
                .map({ ($0, area.intersectionArea(with: $0.frame)) })
                .filter({ $0.1 > 0 })
                .max(by: { $0.1 < $1.1 })?.0
            else {
                logger.error("撮像マスク領域と交差するディスプレイが見つかりません")
                return false
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let information = SCShareableContent.info(for: filter)
            let scale = CGFloat(information.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = max(
                1,
                Int(ceil(display.frame.width * scale))
            )
            configuration.height = max(
                1,
                Int(ceil(display.frame.height * scale))
            )
            configuration.showsCursor = false
            configuration.captureResolution = .best

            let displayImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            try Task.checkCancellation()
            // display フィルタの sourceRect は原点の解釈があいまいなため使わず、
            // 左上原点が保証された CGImage から目的の帯をピクセル単位で切り出す。
            let requestedCropRect = CGRect(
                x: (area.minX - display.frame.minX) * scale,
                y: (area.minY - display.frame.minY) * scale,
                width: area.width * scale,
                height: area.height * scale
            ).integral
            let imageBounds = CGRect(
                x: 0,
                y: 0,
                width: displayImage.width,
                height: displayImage.height
            )
            let cropRect = requestedCropRect.intersection(imageBounds)
            guard !cropRect.isNull,
                  cropRect.width > 0,
                  cropRect.height > 0,
                  let image = displayImage.cropping(to: cropRect)
            else {
                logger.error("撮像マスク画像から対象領域を切り出せませんでした")
                return false
            }

            let panelFrame = CGWindowCoordinateSpace.frame(
                toAppKit: area,
                primaryMaxY: primaryMaxY
            )
            let panel = NSPanel(
                contentRect: panelFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .ignoresCycle,
                .fullScreenAuxiliary,
            ]

            // contentView へ代入すると AppKit が枠へ合わせるため、frame は不要。
            let imageView = NSImageView()
            imageView.imageScaling = .scaleAxesIndependently
            imageView.animates = false
            imageView.image = NSImage(cgImage: image, size: panelFrame.size)
            panel.contentView = imageView
            panel.orderFrontRegardless()
            self.panel = panel
            try? await Task.sleep(for: maskCommitDelay)
            return true
        } catch is CancellationError {
            return false
        } catch {
            // 不完全な帯を出すより、従来どおり一時展開が見える方が安全。
            logger.error("撮像マスクの準備に失敗しました: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func endMasking() {
        guard let panel else { return }
        self.panel = nil
        // self を捕捉すると masker の寿命を遅延タスクへ引き延ばすため、
        // 必要な値だけをローカルへ写して渡す。
        let delay = unmaskDelay
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            panel.orderOut(nil)
        }
    }
}
