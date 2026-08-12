import Foundation
import Testing
import TsuraraCore

private let viewModelTestSuiteName = "TsuraraCoreTests.SettingsViewModel"

private func withViewModelDefaults(
    _ test: (UserDefaults) throws -> Void
) rethrows {
    let defaults = UserDefaults(suiteName: viewModelTestSuiteName)!
    defaults.removePersistentDomain(forName: viewModelTestSuiteName)
    defer { defaults.removePersistentDomain(forName: viewModelTestSuiteName) }

    try test(defaults)
}

@Suite(.serialized)
struct SettingsViewModelTests {
    @Test
    func initializesFromSettingsStore() {
        withViewModelDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.launchAtLogin = true
            store.alwaysHiddenSectionEnabled = true
            store.autoRehideEnabled = false
            store.autoRehideSeconds = 25

            let viewModel = SettingsViewModel(settings: store)

            #expect(viewModel.launchAtLogin)
            #expect(viewModel.alwaysHiddenSectionEnabled)
            #expect(!viewModel.autoRehideEnabled)
            #expect(viewModel.autoRehideSeconds == 25)
        }
    }

    @Test
    func savesValuesThroughSettingsStore() {
        withViewModelDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let viewModel = SettingsViewModel(settings: store)

            viewModel.launchAtLogin = true
            viewModel.alwaysHiddenSectionEnabled = true
            viewModel.autoRehideEnabled = false
            viewModel.autoRehideSeconds = 30

            let reloadedStore = SettingsStore(defaults: defaults)
            #expect(reloadedStore.launchAtLogin)
            #expect(reloadedStore.alwaysHiddenSectionEnabled)
            #expect(!reloadedStore.autoRehideEnabled)
            #expect(reloadedStore.autoRehideSeconds == 30)
        }
    }

    @Test(arguments: [4, 5, 60, 61])
    func usesSettingsStoreClamping(value: Int) {
        withViewModelDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let viewModel = SettingsViewModel(settings: store)

            viewModel.autoRehideSeconds = value

            let expected = min(
                max(value, SettingsStore.autoRehideSecondsRange.lowerBound),
                SettingsStore.autoRehideSecondsRange.upperBound
            )
            #expect(viewModel.autoRehideSeconds == expected)
            #expect(store.autoRehideSeconds == expected)
        }
    }
}
