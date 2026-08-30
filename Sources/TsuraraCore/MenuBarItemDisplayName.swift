import Foundation

public enum MenuBarItemDisplayName {
    /// WindowServer の title と owner 名から、人間向けの表示名を解決する。
    /// バンドル ID の解決は AppKit に依存しないよう呼び出し側から注入する。
    public static func resolve(
        title: String?,
        ownerName: String,
        appNameForBundleID: (String) -> String?
    ) -> String {
        guard let title,
              !title.isEmpty,
              !isGenericTitle(title)
        else { return ownerName }

        if title.contains("."), !title.contains(where: \.isWhitespace) {
            return appNameForBundleID(title) ?? title
        }
        return title
    }

    private static func isGenericTitle(_ title: String) -> Bool {
        if title.allSatisfy(\.isNumber) { return true }

        if title.hasPrefix("Item-") {
            let suffix = title.dropFirst("Item-".count)
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
                return true
            }
        }

        return UUID(uuidString: title) != nil
    }
}
