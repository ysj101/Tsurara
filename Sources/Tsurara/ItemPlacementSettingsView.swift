import CoreGraphics
import SwiftUI
import TsuraraCore

/// 表示名を一覧更新時に解決し、再描画のたびに NSWorkspace を参照しない配置画面。
struct ItemPlacementSettingsView: View {
    struct PlacementRow: Identifiable {
        let displayName: String
        let placement: MenuBarItemPlacement

        var id: CGWindowID {
            placement.window.windowID
        }
    }

    let coordinator: MenuBarItemPlacementCoordinator
    @State private var rows: [PlacementRow] = []
    @State private var errorMessage: String?
    @State private var errorTitle = "アイコンを移動できませんでした"
    @State private var isMoving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cmd ドラッグで非表示セクションへ運べないアイコンは、ここから移動できます。")
                    .font(.caption)
                Spacer()
                Button("再読み込み") { reload() }
                    .disabled(isMoving)
                if isMoving {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18)
                } else {
                    Color.clear.frame(width: 18)
                }
            }
            List {
                placementSection("表示セクション", kind: .visible, destination: .hidden, buttonTitle: "非表示にする")
                placementSection("非表示セクション", kind: .hidden, destination: .visible, buttonTitle: "表示する")
            }
            .listStyle(.inset)
        }
        .padding()
        .onAppear { reload() }
        .alert(
            errorTitle,
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func placementSection(
        _ name: String,
        kind: MenuBarSectionKind,
        destination: MenuBarSectionKind,
        buttonTitle: String
    ) -> some View {
        Section(name) {
            let sectionRows = rows.filter { $0.placement.section == kind }
            if sectionRows.isEmpty {
                Text("項目がありません")
                    .foregroundStyle(.secondary)
            }
            ForEach(sectionRows) { row in
                HStack {
                    Text(row.displayName)
                    Spacer()
                    Button(buttonTitle) { move(row, to: destination) }
                        .disabled(isMoving)
                }
            }
        }
    }

    private func reload() {
        do {
            rows = try coordinator.list().map { placement in
                PlacementRow(
                    displayName: MenuBarItemDisplayName.resolve(
                        title: placement.window.title,
                        ownerName: placement.window.owner.name,
                        appNameForBundleID: BundleIdentifierAppNameResolver.resolve
                    ),
                    placement: placement
                )
            }
        } catch {
            errorTitle = "アイコンの一覧を取得できませんでした"
            errorMessage = error.localizedDescription
        }
    }

    private func move(_ row: PlacementRow, to section: MenuBarSectionKind) {
        isMoving = true
        coordinator.move(row.placement, to: section) { outcome in
            Task { @MainActor in
                defer { isMoving = false }
                switch outcome {
                case .moved:
                    reload()
                case .notPermitted:
                    break
                case let .failed(error):
                    errorTitle = "アイコンを移動できませんでした"
                    errorMessage = error.localizedDescription
                    reload()
                }
            }
        }
    }
}
