import AppKit

/// バンドル ID を、実行中またはインストール済みのアプリの表示名へ解決する。
@MainActor
enum BundleIdentifierAppNameResolver {
    static func resolve(_ bundleIdentifier: String) -> String? {
        if let runningName = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first?.localizedName {
            return runningName
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return nil }
        return FileManager.default.displayName(atPath: applicationURL.path)
    }
}
