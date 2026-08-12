import AppKit
import SwiftUI
import TsuraraCore

@main
struct TsuraraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sectionManager: SectionManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // バンドルの LSUIElement と同じ状態を、バンドルを介さない `swift run` でも
        // 再現するために明示的に設定する。
        NSApp.setActivationPolicy(.accessory)

        let manager = SectionManager(
            settings: SettingsStore(),
            statusItemFactory: { AppKitStatusItem(autosaveName: $0) }
        )

        // LSUIElement アプリはメインメニューを持たず終了手段がないため、
        // メイン区切りの右クリック時だけ終了メニューを表示する。
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Tsurara を終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        guard let mainDivider = manager.hiddenSection.dividerItem as? AppKitStatusItem else {
            // 区切りが取れない状態は終了手段の喪失を意味するため、開発中に即気付けるようにする。
            assertionFailure("メイン区切りが AppKitStatusItem ではない")
            sectionManager = manager
            return
        }
        mainDivider.onRightClick = { [weak mainDivider] in
            guard
                let mainDivider,
                let button = mainDivider.underlying.button
            else { return }

            mainDivider.underlying.menu = menu
            defer { mainDivider.underlying.menu = nil }
            button.performClick(nil)
        }
        sectionManager = manager
    }
}
