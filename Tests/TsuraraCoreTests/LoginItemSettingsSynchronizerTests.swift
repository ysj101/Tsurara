import Foundation
import Testing
import TsuraraCore

private let loginItemTestSuiteName = "TsuraraCoreTests.LoginItemSettingsSynchronizer"

private func withLoginItemDefaults(
    _ test: (UserDefaults) throws -> Void
) rethrows {
    let defaults = UserDefaults(suiteName: loginItemTestSuiteName)!
    defaults.removePersistentDomain(forName: loginItemTestSuiteName)
    defer { defaults.removePersistentDomain(forName: loginItemTestSuiteName) }

    try test(defaults)
}

@MainActor
private final class MockLoginItemManager: LoginItemManaging {
    enum MockError: Error {
        case rejected
    }

    var isRegistered: Bool
    var error: MockError?

    init(isRegistered: Bool, error: MockError? = nil) {
        self.isRegistered = isRegistered
        self.error = error
    }

    func setEnabled(_ enabled: Bool) throws {
        if let error { throw error }
        isRegistered = enabled
    }
}

@Suite(.serialized)
@MainActor
struct LoginItemSettingsSynchronizerTests {
    @Test
    func successfulChangeSavesRegisteredState() throws {
        try withLoginItemDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let manager = MockLoginItemManager(isRegistered: false)
            let synchronizer = LoginItemSettingsSynchronizer(
                settings: store,
                loginItemManager: manager
            )

            let result = try synchronizer.setEnabled(true)

            #expect(result)
            #expect(manager.isRegistered)
            #expect(store.launchAtLogin)
        }
    }

    @Test
    func failedChangeRollsBackToRegisteredState() {
        withLoginItemDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.launchAtLogin = false
            let manager = MockLoginItemManager(
                isRegistered: true,
                error: .rejected
            )
            let synchronizer = LoginItemSettingsSynchronizer(
                settings: store,
                loginItemManager: manager
            )

            #expect(throws: MockLoginItemManager.MockError.rejected) {
                try synchronizer.setEnabled(false)
            }

            #expect(store.launchAtLogin)
        }
    }

    @Test
    func syncUsesSystemStateAsSourceOfTruth() {
        withLoginItemDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.launchAtLogin = true
            let manager = MockLoginItemManager(isRegistered: false)
            let synchronizer = LoginItemSettingsSynchronizer(
                settings: store,
                loginItemManager: manager
            )

            let result = synchronizer.sync()

            #expect(!result)
            #expect(!store.launchAtLogin)
        }
    }
}
