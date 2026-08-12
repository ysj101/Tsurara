import SwiftUI
import TsuraraCore

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    private let loginItemSynchronizer: LoginItemSettingsSynchronizer

    init(
        settings: SettingsStore = SettingsStore(),
        loginItemManager: any LoginItemManaging = SMAppServiceLoginItem()
    ) {
        _viewModel = State(initialValue: SettingsViewModel(settings: settings))
        loginItemSynchronizer = LoginItemSettingsSynchronizer(
            settings: settings,
            loginItemManager: loginItemManager
        )
    }

    var body: some View {
        TabView {
            GeneralSettingsView(
                viewModel: viewModel,
                loginItemSynchronizer: loginItemSynchronizer
            )
            .tabItem {
                Label("一般", systemImage: "gearshape")
            }
            HotkeySettingsTab()
        }
        .frame(width: 440, height: 280)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    let loginItemSynchronizer: LoginItemSettingsSynchronizer
    @State private var loginItemErrorMessage: String?

    var body: some View {
        Form {
            Toggle(
                "ログイン時に起動",
                isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { enabled in
                        updateLaunchAtLogin(enabled)
                    }
                )
            )

            Toggle(
                "常時非表示セクションを有効にする",
                isOn: Binding(
                    get: { viewModel.alwaysHiddenSectionEnabled },
                    set: { enabled in
                        // 永続化は SectionManager 側が生成・破棄の完了後に行う
                        // （二重書き込みと順序逆転を避ける）。VM は結果を再読込する。
                        AppDelegate.sharedSectionManager?
                            .setAlwaysHiddenSectionEnabled(enabled)
                        viewModel.refresh()
                    }
                )
            )

            HStack {
                Toggle(
                    "自動再非表示を有効にする",
                    isOn: Binding(
                        get: { viewModel.autoRehideEnabled },
                        set: { enabled in
                            viewModel.autoRehideEnabled = enabled
                            // 展開中の有効化を即座に反映する（再トグル待ちにしない）。
                            AppDelegate.sharedSectionManager?.autoRehideSettingDidChange()
                        }
                    )
                )
                Spacer()
                Stepper(
                    "\(viewModel.autoRehideSeconds) 秒",
                    value: $viewModel.autoRehideSeconds,
                    in: SettingsStore.autoRehideSecondsRange
                )
                .disabled(!viewModel.autoRehideEnabled)
            }

            Button("常時非表示セクションを一時的に表示する") {
                AppDelegate.sharedSectionManager?
                    .temporarilyShowAlwaysHiddenSection()
            }
            .disabled(!viewModel.alwaysHiddenSectionEnabled)
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            viewModel.refresh()
            // システム設定側で変更されている可能性があるため、実状態と同期する。
            viewModel.launchAtLogin = loginItemSynchronizer.sync()
        }
        .alert(
            "ログイン時起動を変更できませんでした",
            isPresented: Binding(
                get: { loginItemErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { loginItemErrorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loginItemErrorMessage ?? "不明なエラーが発生しました。")
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            viewModel.launchAtLogin = try loginItemSynchronizer.setEnabled(enabled)
        } catch {
            // Synchronizer は失敗時にも保存値を実状態へ戻す。表示も同じ値へ戻す。
            viewModel.launchAtLogin = loginItemSynchronizer.sync()
            loginItemErrorMessage = error.localizedDescription
        }
    }
}
