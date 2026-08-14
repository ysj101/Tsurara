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
            store.autoCloseEnabled = false
            store.autoCloseSeconds = 25

            let viewModel = SettingsViewModel(settings: store)

            #expect(viewModel.launchAtLogin)
            #expect(viewModel.alwaysHiddenSectionEnabled)
            #expect(!viewModel.autoCloseEnabled)
            #expect(viewModel.autoCloseSeconds == 25)
        }
    }

    @Test
    func savesValuesThroughSettingsStore() {
        withViewModelDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let viewModel = SettingsViewModel(settings: store)

            viewModel.launchAtLogin = true
            viewModel.alwaysHiddenSectionEnabled = true
            viewModel.autoCloseEnabled = false
            viewModel.autoCloseSeconds = 30

            let reloadedStore = SettingsStore(defaults: defaults)
            #expect(reloadedStore.launchAtLogin)
            #expect(reloadedStore.alwaysHiddenSectionEnabled)
            #expect(!reloadedStore.autoCloseEnabled)
            #expect(reloadedStore.autoCloseSeconds == 30)
        }
    }

    @Test(arguments: [4, 5, 60, 61])
    func usesSettingsStoreClamping(value: Int) {
        withViewModelDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let viewModel = SettingsViewModel(settings: store)

            viewModel.autoCloseSeconds = value

            let expected = min(
                max(value, SettingsStore.autoCloseSecondsRange.lowerBound),
                SettingsStore.autoCloseSecondsRange.upperBound
            )
            #expect(viewModel.autoCloseSeconds == expected)
            #expect(store.autoCloseSeconds == expected)
        }
    }
}
