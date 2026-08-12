#!/bin/sh
# ユニットテストを実行する。
# Xcode のない環境（CommandLineTools のみ）では `swift test` が swift-testing の
# テストを発見できないため、実行ターゲット TsuraraTests をビルドして直接実行する。
# Xcode がある環境では通常の `swift test` に委譲する（Package.swift と同じ判定）。
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

case "$(xcode-select -p 2>/dev/null || true)" in
*CommandLineTools*)
    swift build --product TsuraraTests
    exec .build/debug/TsuraraTests "$@"
    ;;
*)
    exec swift test "$@"
    ;;
esac
