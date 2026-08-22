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

The script creates `build/Tsurara.app` (not notarized). macOS may require you to approve it before launching it.

署名は次の順で選ぶ。

1. `TSURARA_SIGN_IDENTITY`（未設定なら `Tsurara Dev`）という名前の codesigning ID がキーチェーンにあれば、それで署名する。
2. なければ ad-hoc 署名にフォールバックし、警告を出す。

ad-hoc 署名の designated requirement は cdhash だけで構成されるため、再ビルドのたびに TCC からは別アプリと見なされ、アクセシビリティと画面収録の許可がやり直しになる。自己署名の証明書を「キーチェーンアクセス」で 1 つ作っておくと、許可が再ビルドをまたいで保持される。
