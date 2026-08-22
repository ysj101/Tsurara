import CoreGraphics
import Foundation

/// サブバーを配置するときに参照する 1 画面分の座標情報。
///
/// `frame` はメニューバーを含む画面全体、`visibleFrame` はメニューバーと Dock を
/// 除いた安全な表示領域を表す。AppKit への依存を持たないため配置計算を単体で検証できる。
public struct SubBarScreenGeometry: Equatable, Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// Tsurara アイコンと画面群から、画面内に収まるパネル座標を求める境界。
public protocol SubBarPanelLayoutCalculating: Sendable {
    func panelFrame(
        anchorFrame: CGRect,
        desiredSize: CGSize,
        screens: [SubBarScreenGeometry]
    ) -> CGRect?
}

/// マルチディスプレイと画面端を考慮する既定の配置計算。
public struct SubBarPanelLayoutCalculator: SubBarPanelLayoutCalculating {
    public init() {}

    public func panelFrame(
        anchorFrame: CGRect,
        desiredSize: CGSize,
        screens: [SubBarScreenGeometry]
    ) -> CGRect? {
        guard let screen = targetScreen(for: anchorFrame, screens: screens) else {
            return nil
        }

        let visible = screen.visibleFrame
        let width = min(max(0, desiredSize.width), max(0, visible.width))
        let height = min(max(0, desiredSize.height), max(0, visible.height))

        // アイコンの中央へ合わせ、左右端では visibleFrame 内へ押し戻す。
        let centeredX = anchorFrame.midX - width / 2
        let x = clamp(centeredX, lower: visible.minX, upper: visible.maxX - width)

        // NSScreen 座標は下から上。通常はアイコン直下へ置き、ノッチ／メニューバーや
        // Dock に重ならないよう visibleFrame の上下端で補正する。
        let belowAnchorY = anchorFrame.minY - height
        let y = clamp(belowAnchorY, lower: visible.minY, upper: visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func targetScreen(
        for anchorFrame: CGRect,
        screens: [SubBarScreenGeometry]
    ) -> SubBarScreenGeometry? {
        guard !screens.isEmpty else { return nil }

        // ステータスアイテムと最も広く交差する画面を優先する。画面境界上などで
        // 交差面積がない場合は、アンカー中心から最も近い画面を選ぶ。
        if let intersecting = screens
            .map({ ($0, anchorFrame.intersectionArea(with: $0.frame)) })
            .filter({ $0.1 > 0 })
            .max(by: { $0.1 < $1.1 })?.0
        {
            return intersecting
        }

        let anchorCenter = CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)
        return screens.min {
            squaredDistance(from: anchorCenter, to: $0.frame)
                < squaredDistance(from: anchorCenter, to: $1.frame)
        }
    }

    private func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let closestX = clamp(point.x, lower: rect.minX, upper: rect.maxX)
        let closestY = clamp(point.y, lower: rect.minY, upper: rect.maxY)
        let dx = point.x - closestX
        let dy = point.y - closestY
        return dx * dx + dy * dy
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}

/// Core の状態制御から AppKit の NSPanel を分離する表示境界。
@MainActor
public protocol SubBarPanelPresenting: AnyObject {
    func present(
        items: [ImagedMenuBarItem],
        anchorFrame: @escaping @MainActor () -> CGRect?
    ) -> Bool
    func dismiss()
}

public enum SubBarPresentationState: Equatable, Sendable {
    case closed
    case opening
    case open
}

/// サブバーの開閉状態を一元管理する。
///
/// `toggle()` の `.beginOpening` を受けたアプリ層が権限確認と撮像を行い、完了後に
/// `open(items:anchorFrame:)` を呼ぶ。撮像中の再トグルも確実に close へ戻せる。
@MainActor
public final class SubBarPresentationController {
    public typealias Generation = UInt64

    public enum ToggleAction: Equatable, Sendable {
        case beginOpening(Generation)
        case close
    }

    private enum CycleState {
        case closed
        case opening(Generation)
        case open(Generation)
    }

    public var state: SubBarPresentationState {
        switch cycleState {
        case .closed: .closed
        case .opening: .opening
        case .open: .open
        }
    }

    private let presenter: any SubBarPanelPresenting
    private var cycleState: CycleState = .closed
    private var nextGeneration: Generation = 0

    public init(presenter: any SubBarPanelPresenting) {
        self.presenter = presenter
    }

    @discardableResult
    public func toggle() -> ToggleAction {
        switch cycleState {
        case .closed:
            nextGeneration &+= 1
            cycleState = .opening(nextGeneration)
            return .beginOpening(nextGeneration)
        case .opening, .open:
            close()
            return .close
        }
    }

    /// 指定世代が現在の opening サイクルを所有している場合だけ表示する。
    @discardableResult
    public func open(
        items: [ImagedMenuBarItem],
        generation: Generation,
        anchorFrame: @escaping @MainActor () -> CGRect?
    ) -> Bool {
        guard case let .opening(currentGeneration) = cycleState,
              currentGeneration == generation
        else { return false }
        guard presenter.present(items: items, anchorFrame: anchorFrame) else {
            cycleState = .closed
            return false
        }
        cycleState = .open(generation)
        return true
    }

    public func close() {
        switch cycleState {
        case .closed:
            return
        case .opening:
            break
        case .open:
            presenter.dismiss()
        }
        cycleState = .closed
    }

    /// stale な非同期処理から現行サイクルを閉じないための世代付き close。
    @discardableResult
    public func close(generation: Generation) -> Bool {
        guard ownsCycle(generation) else { return false }
        if case .open = cycleState {
            presenter.dismiss()
        }
        cycleState = .closed
        return true
    }

    public func ownsCycle(_ generation: Generation) -> Bool {
        switch cycleState {
        case let .opening(currentGeneration), let .open(currentGeneration):
            currentGeneration == generation
        case .closed:
            false
        }
    }

    /// Task スロットの解放時に、より新しい世代を誤って消さないために使う。
    public func isLatestGeneration(_ generation: Generation) -> Bool {
        nextGeneration == generation
    }
}
