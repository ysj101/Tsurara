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
            return []
        }

        let statusLevel = CGWindowLevelForKey(.statusWindow)
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

            return MenuBarItemWindow(
                windowID: windowID,
                frame: frame,
                ownerPID: ownerPID,
                ownerName: dictionary[kCGWindowOwnerName as String] as? String ?? ""
            )
        }
        .sorted {
            if $0.frame.minY != $1.frame.minY {
                return $0.frame.minY < $1.frame.minY
            }
            if $0.frame.minX != $1.frame.minX {
                return $0.frame.minX < $1.frame.minX
            }
            return $0.windowID < $1.windowID
        }
    }
}
