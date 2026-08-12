import SwiftUI
import TsuraraCore

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(settings: SettingsStore = SettingsStore()) {
        _viewModel = State(initialValue: SettingsViewModel(settings: settings))
    }

    var body: some View {
        TabView {
            GeneralSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("一般", systemImage: "gearshape")
                }
            HotkeySettingsTab()
        }
        .frame(width: 440, height: 260)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            // SMAppService への実登録は #13 で接続する（現状は値の保存のみ）。
            Toggle("ログイン時に起動", isOn: $viewModel.launchAtLogin)

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
        .onAppear { viewModel.refresh() }
    }
}
