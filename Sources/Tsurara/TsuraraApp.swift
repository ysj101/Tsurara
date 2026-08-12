import AppKit
import SwiftUI

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
    private var statusItem: AppKitStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // バンドルの LSUIElement と同じ状態を、バンドルを介さない `swift run` でも
        // 再現するために明示的に設定する。
        NSApp.setActivationPolicy(.accessory)

        let item = AppKitStatusItem()
        item.setIcon(symbolName: "snowflake", accessibilityDescription: "Tsurara")

        // LSUIElement アプリはメインメニューを持たず終了手段がないため、
        // 暫定でステータスアイテムのメニューから終了できるようにする。
        // メニューを設定している間は onClick は発火しない（#7 でクリックトグルに
        // 置き換える際に整理する）。
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Tsurara を終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.underlying.menu = menu
        statusItem = item
    }
}
