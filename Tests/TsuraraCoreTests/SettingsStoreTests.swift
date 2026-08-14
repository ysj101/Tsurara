import Foundation
import Testing
import TsuraraCore

// UUID 入りの使い捨て suite は ~/Library/Preferences に plist を無限に残すため、
// 固定名の suite を使い、前後で確実に掃除する。固定名を共有するため、
// このファイルのテストは .serialized で直列実行する。
private let testSuiteName = "TsuraraCoreTests.SettingsStore"

private func withIsolatedDefaults(
    _ test: (UserDefaults) throws -> Void
) rethrows {
    let defaults = UserDefaults(suiteName: testSuiteName)!
    defaults.removePersistentDomain(forName: testSuiteName)
    defer { defaults.removePersistentDomain(forName: testSuiteName) }

    try test(defaults)
}

@Suite(.serialized)
struct SettingsStoreTests {

@Test
func settingsStoreUsesExpectedDefaults() {
    withIsolatedDefaults { defaults in
        let store = SettingsStore(defaults: defaults)

        #expect(store.launchAtLogin == false)
        #expect(store.alwaysHiddenSectionEnabled == false)
        #expect(store.autoRehideEnabled == true)
        #expect(store.autoRehideSeconds == SettingsStore.defaultAutoRehideSeconds)
        #expect(store.toggleHotkey == nil)
        #expect(store.hasRequestedScreenCaptureAccess == false)
        #expect(store.hasRequestedAccessibilityAccess == false)
    }
}

@Test
func settingsStoreRoundTripsEveryProperty() {
    withIsolatedDefaults { defaults in
        let store = SettingsStore(defaults: defaults)
        let hotkey = HotkeyConfiguration(keyCode: 49, modifierFlags: 1_048_576)

        store.launchAtLogin = true
        store.alwaysHiddenSectionEnabled = true
        store.autoRehideEnabled = false
        store.autoRehideSeconds = 30
        store.toggleHotkey = hotkey
        store.hasRequestedScreenCaptureAccess = true
        store.hasRequestedAccessibilityAccess = true

        let reloadedStore = SettingsStore(defaults: defaults)
        #expect(reloadedStore.launchAtLogin == true)
        #expect(reloadedStore.alwaysHiddenSectionEnabled == true)
        #expect(reloadedStore.autoRehideEnabled == false)
        #expect(reloadedStore.autoRehideSeconds == 30)
        #expect(reloadedStore.toggleHotkey == hotkey)
        #expect(reloadedStore.hasRequestedScreenCaptureAccess == true)
        #expect(reloadedStore.hasRequestedAccessibilityAccess == true)

        reloadedStore.toggleHotkey = nil
        reloadedStore.hasRequestedScreenCaptureAccess = false
        reloadedStore.hasRequestedAccessibilityAccess = false
        #expect(SettingsStore(defaults: defaults).toggleHotkey == nil)
        #expect(SettingsStore(defaults: defaults).hasRequestedScreenCaptureAccess == false)
        #expect(SettingsStore(defaults: defaults).hasRequestedAccessibilityAccess == false)
    }
}

@Test
func screenCaptureRequestFlagUsesReverseDNSKey() {
    withIsolatedDefaults { defaults in
        let store = SettingsStore(defaults: defaults)

        store.hasRequestedScreenCaptureAccess = true

        #expect(
            defaults.bool(
                forKey: "com.ysj.Tsurara.hasRequestedScreenCaptureAccess"
            )
        )
    }
}

@Test
func accessibilityRequestFlagUsesReverseDNSKey() {
    withIsolatedDefaults { defaults in
        let store = SettingsStore(defaults: defaults)

        store.hasRequestedAccessibilityAccess = true

        #expect(
            defaults.bool(
                forKey: "com.ysj.Tsurara.hasRequestedAccessibilityAccess"
            )
        )
    }
}

@Test(arguments: [
    (value: 4, expected: 5),
    (value: 5, expected: 5),
    (value: 60, expected: 60),
    (value: 61, expected: 60),
])
func autoRehideSecondsIsClampedBeforePersistence(value: Int, expected: Int) {
    withIsolatedDefaults { defaults in
        let store = SettingsStore(defaults: defaults)

        store.autoRehideSeconds = value

        #expect(store.autoRehideSeconds == expected)
        #expect(SettingsStore(defaults: defaults).autoRehideSeconds == expected)
    }
}

@Test
func autoRehideSecondsClampsExternallyStoredValues() {
    withIsolatedDefaults { defaults in
        let store = SettingsStore(defaults: defaults)

        // defaults write 等でストアを介さずに書き込まれた値も範囲内に丸めて返す。
        defaults.set(0, forKey: "com.ysj.Tsurara.autoRehideSeconds")
        #expect(store.autoRehideSeconds == 5)

        // 型不一致（文字列など）は既定値へフォールバックする。
        defaults.set("fifteen", forKey: "com.ysj.Tsurara.autoRehideSeconds")
        #expect(store.autoRehideSeconds == SettingsStore.defaultAutoRehideSeconds)
    }
}

}
