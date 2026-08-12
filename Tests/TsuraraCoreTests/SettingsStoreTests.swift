import Foundation
import Testing
import TsuraraCore

private func withIsolatedDefaults(
    _ test: (UserDefaults) throws -> Void
) rethrows {
    let suiteName = "TsuraraCoreTests.SettingsStore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    try test(defaults)
}

@Test
func settingsStoreUsesExpectedDefaults() {
    withIsolatedDefaults { defaults in
        let store = SettingsStore(defaults: defaults)

        #expect(store.launchAtLogin == false)
        #expect(store.alwaysHiddenSectionEnabled == false)
        #expect(store.autoRehideEnabled == true)
        #expect(store.autoRehideSeconds == 15)
        #expect(store.toggleHotkey == nil)
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

        let reloadedStore = SettingsStore(defaults: defaults)
        #expect(reloadedStore.launchAtLogin == true)
        #expect(reloadedStore.alwaysHiddenSectionEnabled == true)
        #expect(reloadedStore.autoRehideEnabled == false)
        #expect(reloadedStore.autoRehideSeconds == 30)
        #expect(reloadedStore.toggleHotkey == hotkey)

        reloadedStore.toggleHotkey = nil
        #expect(SettingsStore(defaults: defaults).toggleHotkey == nil)
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
        #expect(defaults.integer(forKey: "autoRehideSeconds") == expected)
        #expect(SettingsStore(defaults: defaults).autoRehideSeconds == expected)
    }
}
