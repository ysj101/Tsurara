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
        let displays = AppKitScreenGeometry.cgFrames
        return dictionaries.compactMap { dictionary in
            guard
                let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.int32Value,
                let windowID = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let ownerPID = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                let bounds = dictionary[kCGWindowBounds as String] as? [String: NSNumber],
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                frame.width > 0,
                frame.height > 0,
                MenuBarItemWindowCandidate.isMenuBarItemWindow(
                    layer: layer,
                    frame: frame,
                    statusWindowLevel: statusLevel,
                    displayFrames: displays
                )
            else { return nil }

            let displayFrame = displays.first { frame.intersects($0) }
            return MenuBarItemWindow(
                windowID: windowID,
                frame: frame,
                owner: MenuBarItemOwner(
                    processIdentifier: ownerPID,
                    name: dictionary[kCGWindowOwnerName as String] as? String ?? ""
                ),
                title: dictionary[kCGWindowName as String] as? String,
                displayFrame: displayFrame
            )
        }
    }
}
