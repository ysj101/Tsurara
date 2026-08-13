# Tsurara

Tsurara is a macOS 14+ menu bar app for organizing menu bar items. This repository uses Swift Package Manager and does not require an Xcode project.

## Make targets

```sh
make test   # ユニットテスト（Scripts/test.sh）
make build  # デバッグビルド
make app    # build/Tsurara.app を生成（Scripts/make-app.sh）
make run    # app を生成して起動
make stop   # 起動中の Tsurara を終了
make clean  # ビルド成果物を削除
```

## Test

```sh
Scripts/test.sh
```

Xcode がある環境ではそのまま `swift test` に委譲する。Xcode のない環境（Command Line Tools のみ）では `swift test` がテストを 1 件も実行せず成功してしまうため、実行ターゲット `TsuraraCoreTests` をビルドして直接実行する。環境判定は `DEVELOPER_DIR` 環境変数、なければ `xcode-select` の実体リンク（`/var/db/xcode_select_link`）の順で、`Package.swift` と `Scripts/test.sh` が同じ規則を使う。

## Build the app bundle

```sh
Scripts/make-app.sh
```

The script creates `build/Tsurara.app` with an ad-hoc code signature (not notarized). macOS may require you to approve it before launching it.
