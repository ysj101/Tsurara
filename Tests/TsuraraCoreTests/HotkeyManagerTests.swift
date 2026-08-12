import Foundation
import Testing
import TsuraraCore

private let hotkeyTestSuiteName = "TsuraraCoreTests.HotkeyManager"

@MainActor
private final class MockHotkeyRegistrar: HotkeyRegistering {
    var shouldRegister = true
    private(set) var registeredConfigurations: [HotkeyConfiguration] = []
    private(set) var unregisterCallCount = 0
    private(set) var onPress: (@MainActor () -> Void)?

    func register(
        _ configuration: HotkeyConfiguration,
        onPress: @escaping @MainActor () -> Void
    ) -> Bool {
        guard shouldRegister else { return false }
        registeredConfigurations.append(configuration)
        self.onPress = onPress
        return true
    }

    func unregister() {
        unregisterCallCount += 1
        onPress = nil
    }

    func press() {
        onPress?()
    }
}

@MainActor
@Suite(.serialized)
struct HotkeyManagerTests {
    private let configuration = HotkeyConfiguration(
        keyCode: 49,
        modifierFlags: 1_048_576
    )

    @Test
    func restoreRegistersSavedHotkey() {
        withStore { store in
            store.toggleHotkey = configuration
            let registrar = MockHotkeyRegistrar()
            let manager = HotkeyManager(
                settings: store,
                registrar: registrar,
                onToggle: {}
            )

            manager.restoreFromSettings()

            #expect(registrar.registeredConfigurations == [configuration])
        }
    }

    @Test
    func restoreDoesNotRegisterWithoutSavedHotkey() {
        withStore { store in
            let registrar = MockHotkeyRegistrar()
            let manager = HotkeyManager(
                settings: store,
                registrar: registrar,
                onToggle: {}
            )

            manager.restoreFromSettings()

            #expect(registrar.registeredConfigurations.isEmpty)
        }
    }

    @Test
    func assignRegistersAndSavesHotkey() {
        withStore { store in
            let registrar = MockHotkeyRegistrar()
            let manager = HotkeyManager(
                settings: store,
                registrar: registrar,
                onToggle: {}
            )

            let result = manager.assign(configuration)

            #expect(result)
            #expect(registrar.registeredConfigurations == [configuration])
            #expect(store.toggleHotkey == configuration)
        }
    }

    @Test
    func assigningNilUnregistersAndClearsSavedHotkey() {
        withStore { store in
            store.toggleHotkey = configuration
            let registrar = MockHotkeyRegistrar()
            let manager = HotkeyManager(
                settings: store,
                registrar: registrar,
                onToggle: {}
            )

            let result = manager.assign(nil)

            #expect(result)
            #expect(registrar.unregisterCallCount == 1)
            #expect(store.toggleHotkey == nil)
        }
    }

    @Test
    func failedAssignmentDoesNotSaveHotkey() {
        withStore { store in
            let existing = HotkeyConfiguration(keyCode: 0, modifierFlags: 0)
            store.toggleHotkey = existing
            let registrar = MockHotkeyRegistrar()
            registrar.shouldRegister = false
            let manager = HotkeyManager(
                settings: store,
                registrar: registrar,
                onToggle: {}
            )

            let result = manager.assign(configuration)

            #expect(result == false)
            #expect(registrar.registeredConfigurations.isEmpty)
            #expect(store.toggleHotkey == existing)
        }
    }

    @Test
    func pressingRegisteredHotkeyInvokesToggleAction() {
        withStore { store in
            let registrar = MockHotkeyRegistrar()
            var toggleCount = 0
            let manager = HotkeyManager(
                settings: store,
                registrar: registrar,
                onToggle: { toggleCount += 1 }
            )
            #expect(manager.assign(configuration))

            registrar.press()

            #expect(toggleCount == 1)
        }
    }

    private func withStore(_ test: (SettingsStore) -> Void) {
        let defaults = UserDefaults(suiteName: hotkeyTestSuiteName)!
        defaults.removePersistentDomain(forName: hotkeyTestSuiteName)
        defer { defaults.removePersistentDomain(forName: hotkeyTestSuiteName) }
        test(SettingsStore(defaults: defaults))
    }
}
