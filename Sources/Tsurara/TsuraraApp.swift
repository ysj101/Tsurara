import AppKit
import SwiftUI
import TsuraraCore

@main
struct TsuraraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: appDelegate.settings)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var sharedSectionManager: SectionManager?

    let settings = SettingsStore()
    private var sectionManager: SectionManager?
    private var menuTrackingObservers: [any NSObjectProtocol] = []
    private var openMenuCount = 0
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // バンドルの LSUIElement と同じ状態を、バンドルを介さない `swift run` でも
        // 再現するために明示的に設定する。
        NSApp.setActivationPolicy(.accessory)

        let manager = SectionManager(
            settings: settings,
            statusItemFactory: { AppKitStatusItem(autosaveName: $0) }
        )
        Self.sharedSectionManager = manager
        observeMenuTracking(for: manager)
        let hotkeyManager = HotkeyManager(
            settings: settings,
            registrar: CarbonHotkeyRegistrar(),
            onToggle: { manager.toggleHiddenSection() }
        )
        hotkeyManager.restoreFromSettings()
        self.hotkeyManager = hotkeyManager

        // LSUIElement アプリはメインメニューを持たず終了手段がないため、
        // 常に画面上に残るトグル項目の右クリック時だけ終了メニューを表示する。
        let menu = NSMenu()
        // LSUIElement アプリはアプリメニュー（Cmd+,）を持たないため、
        // 設定画面へはこのメニューが唯一の経路になる。
        let settingsItem = NSMenuItem(
            title: "設定…",
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Tsurara を終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        guard let toggleItem = manager.toggleItem as? AppKitStatusItem else {
            // トグル項目が取れない状態は終了手段の喪失を意味するため、開発中に即気付けるようにする。
            assertionFailure("トグル項目が AppKitStatusItem ではない")
            sectionManager = manager
            return
        }
        toggleItem.onRightClick = { [weak toggleItem] in
            guard
                let toggleItem,
                let button = toggleItem.underlying.button
            else { return }

            // menu プロパティへの一時代入 + performClick はボタンの target/action を
            // AppKit に奪われる・再入するなど挙動が不定なため、popUp で直接表示する。
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.height + 4),
                in: button
            )
        }
        // 保険: autosave 位置の復元や Cmd ドラッグでトグル項目が ◇ より左へ行くと
        // collapse 時に画面外へ押し出され、終了手段を失う。セパレータ側にも同じ
        // 終了メニューを付け、常にどちらかの右クリックで終了できるようにする。
        if let mainDivider = manager.hiddenSection.dividerItem as? AppKitStatusItem {
            mainDivider.onRightClick = { [weak mainDivider] in
                guard
                    let mainDivider,
                    let button = mainDivider.underlying.button
                else { return }
                menu.popUp(
                    positioning: nil,
                    at: NSPoint(x: 0, y: button.bounds.height + 4),
                    in: button
                )
            }
        }
        sectionManager = manager
    }
}

extension AppDelegate {
    /// SwiftUI の Settings シーンを開く。accessory アプリはそのままだと
    /// ウィンドウが最前面に出ないため、明示的にアクティブ化する。
    @objc fileprivate func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // macOS 14+ の SwiftUI Settings シーンを開く標準セレクタ。
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// メニューの追跡状態を SectionManager へ伝える。
    /// NSMenu の通知は自プロセスのメニューにのみ届くため、他アプリのメニュー展開は
    /// 検知できない（MVP の既知の制約。spec の「いずれかのメニュー」への完全対応は
    /// 追加権限なしでは不可能なため、自アプリのメニューのみ対象とする）。
    fileprivate func observeMenuTracking(for manager: SectionManager) {
        let center = NotificationCenter.default
        let begin = center.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.openMenuCount += 1
                self.sectionManager?.isMenuTrackingActive = true
            }
        }
        let end = center.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.openMenuCount = max(0, self.openMenuCount - 1)
                if self.openMenuCount == 0 {
                    self.sectionManager?.isMenuTrackingActive = false
                }
            }
        }
        menuTrackingObservers = [begin, end]
    }
}
