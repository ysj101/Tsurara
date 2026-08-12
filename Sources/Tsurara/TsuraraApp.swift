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
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "snowflake",
            accessibilityDescription: "Tsurara"
        )

        // LSUIElement アプリはメインメニューを持たず終了手段がないため、
        // 暫定でステータスアイテムのメニューから終了できるようにする。
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Tsurara を終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu
        statusItem = item
    }
}
