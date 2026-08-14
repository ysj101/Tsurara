import AppKit
import CoreGraphics
import Foundation
import TsuraraCore

/// WindowServer が公開する status-level window からメニューバー項目を列挙する。
@MainActor
final class CGWindowMenuBarItemWindowLister: MenuBarItemWindowListing {
    func listMenuBarItemWindows() throws -> [MenuBarItemWindow] {
        // optionOnScreenOnly を付けると、区切りの length によって負の x 座標へ
        // 押し出された項目が消える。その項目こそ撮像対象なので全ウィンドウを取得する。
        guard let dictionaries = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            throw MenuBarItemWindowListingError.windowListUnavailable
        }

        let statusLevel = CGWindowLevelForKey(.statusWindow)
        let displays = Self.cgScreenFrames()
        return dictionaries.compactMap { dictionary in
            guard
                let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.int32Value,
                layer == statusLevel,
                let windowID = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let ownerPID = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                let bounds = dictionary[kCGWindowBounds as String] as? [String: NSNumber],
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                frame.width > 0,
                frame.height > 0
            else { return nil }

            let displayFrame = displays.first { frame.intersects($0) }

            return MenuBarItemWindow(
                windowID: windowID,
                frame: frame,
                owner: MenuBarItemOwner(
                    processIdentifier: ownerPID,
                    name: dictionary[kCGWindowOwnerName as String] as? String ?? ""
                ),
                displayFrame: displayFrame
            )
        }
    }

    /// NSScreen の左下原点から CGWindow の主画面左上原点へ変換する。
    private static func cgScreenFrames() -> [CGRect] {
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return [] }
        return NSScreen.screens.map { screen in
            CGRect(
                x: screen.frame.minX,
                y: primaryMaxY - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
        }
    }
}
