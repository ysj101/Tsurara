# Tsurara

Tsurara is a macOS 14+ menu bar app for organizing menu bar items. This repository uses Swift Package Manager and does not require an Xcode project.

## Test

```sh
Scripts/test.sh
```

Xcode のない環境（Command Line Tools のみ）では `swift test` が swift-testing のテストを発見できないため、実行ターゲット `TsuraraTests` 経由でテストを実行する。

## Build the app bundle

```sh
Scripts/make-app.sh
```

The script creates `build/Tsurara.app`. Because this initial development bundle is unsigned, macOS may require you to approve it before launching it.
