# Tsurara

Tsurara is a macOS 14+ menu bar app for organizing menu bar items. This repository uses Swift Package Manager and does not require an Xcode project.

## Test

```sh
Scripts/test.sh
```

Xcode がある環境ではそのまま `swift test` に委譲する。Xcode のない環境（Command Line Tools のみ）では `swift test` がテストを 1 件も実行せず成功してしまうため、実行ターゲット `TsuraraTests` をビルドして直接実行する（判定は `xcode-select -p`）。

## Build the app bundle

```sh
Scripts/make-app.sh
```

The script creates `build/Tsurara.app` with an ad-hoc code signature (not notarized). macOS may require you to approve it before launching it.
