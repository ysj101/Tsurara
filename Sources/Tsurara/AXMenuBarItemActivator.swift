import ApplicationServices
import CoreGraphics
import Foundation
import TsuraraCore

/// 画面上へ一時展開されたステータス項目を公開 Accessibility API で押す。
@MainActor
final class AXMenuBarItemActivator: MenuBarItemAccessibilityActivating {
    private let messagingTimeout: Float = 0.25
    private let frameTolerance: CGFloat = 10
    private let settlePollInterval = Duration.milliseconds(20)
    private let settlePollLimit = 30

    func activate(
        at point: CGPoint,
        itemFrame: CGRect,
        button: MenuBarItemClickButton
    ) async throws -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        setMessagingTimeout(on: systemWide)

        // 一時展開はウィンドウを動かすが、システム側のメニューバー項目レイアウトが
        // 追随するまでには間がある。CGWindow の frame だけを見て押すと、まだ
        // 折り畳み時のレイアウトに向けて操作してしまい、メニューが画面外に開く。
        // その座標を項目として認識するまで待つことを、操作の前提条件にする。
        guard let element = try await settledMenuBarItem(
            at: point,
            itemFrame: itemFrame,
            systemWide: systemWide
        ) else {
            return nil
        }

        let preferredActions: [String]
        switch button {
        case .left:
            preferredActions = [kAXPressAction as String, kAXShowMenuAction as String]
        case .right:
            preferredActions = [kAXShowMenuAction as String, kAXPressAction as String]
        }
        let supportedActions = actionNames(of: element)
        var elementPID: pid_t = 0
        AXUIElementGetPid(element, &elementPID)
        for action in preferredActions where supportedActions.contains(action) {
            let result = AXUIElementPerformAction(element, action as CFString)
            // メニューを開いた対象はモーダルなトラッキングループへ入り、AX
            // メッセージに応答できなくなる。そのため成功したときほど timeout
            // 相当の cannotComplete になり得る。ここで CGEvent へ進むと、開いた
            // メニューを即座に閉じるので cannotComplete も成功として扱う。
            guard result == .success || result == .cannotComplete else {
                continue
            }
            return elementPID
        }
        return nil
    }

    /// 座標がメニューバー項目として認識され、その frame が対象と重なるまで待つ。
    private func settledMenuBarItem(
        at point: CGPoint,
        itemFrame: CGRect,
        systemWide: AXUIElement
    ) async throws -> AXUIElement? {
        for _ in 0..<settlePollLimit {
            if let element = menuBarItem(at: point, systemWide: systemWide),
               let elementFrame = frame(of: element),
               elementFrame.insetBy(
                   dx: -frameTolerance,
                   dy: -frameTolerance
               ).intersects(itemFrame)
            {
                return element
            }
            try await Task.sleep(for: settlePollInterval)
        }
        return nil
    }

    /// 座標にあるメニューバー項目。ヒットテストが項目を返さない場合は、
    /// ヒットした要素の所有アプリの extras menu bar から座標を含む子を探す。
    private func menuBarItem(
        at point: CGPoint,
        systemWide: AXUIElement
    ) -> AXUIElement? {
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &hitElement
        ) == .success, let hitElement else {
            return nil
        }
        setMessagingTimeout(on: hitElement)
        if role(of: hitElement) == kAXMenuBarItemRole as String {
            return hitElement
        }
        return extrasMenuBarItem(at: point, hitElement: hitElement)
    }

    private func extrasMenuBarItem(
        at point: CGPoint,
        hitElement: AXUIElement
    ) -> AXUIElement? {
        var ownerPID: pid_t = 0
        guard AXUIElementGetPid(hitElement, &ownerPID) == .success else {
            return nil
        }

        let application = AXUIElementCreateApplication(ownerPID)
        setMessagingTimeout(on: application)
        guard let extrasMenuBar = attributeElement(
            kAXExtrasMenuBarAttribute as CFString,
            of: application
        ) else {
            return nil
        }
        setMessagingTimeout(on: extrasMenuBar)

        guard let children = attributeElements(
            kAXChildrenAttribute as CFString,
            of: extrasMenuBar
        ) else {
            return nil
        }
        for child in children {
            setMessagingTimeout(on: child)
        }
        return children.first { child in
            frame(of: child)?.contains(point) == true
        }
    }

    private func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
            AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeValue
            ) == .success,
            let positionValue,
            let sizeValue,
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(
            positionValue as! AXValue,
            .cgPoint,
            &position
        ), AXValueGetValue(
            sizeValue as! AXValue,
            .cgSize,
            &size
        ) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func actionNames(of element: AXUIElement) -> Set<String> {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let names = names as? [String]
        else {
            return []
        }
        return Set(names)
    }

    private func attributeElement(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &value
        ) == .success, let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func attributeElements(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &value
        ) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private func setMessagingTimeout(on element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }
}
