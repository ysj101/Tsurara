#!/bin/sh
# ユニットテストを実行する。
# Xcode のない環境（CommandLineTools のみ）では `swift test` が swift-testing の
# テストを発見できないため、実行ターゲット TsuraraTests を経由して実行する。
set -eu
cd "$(dirname "$0")/.."
exec swift run TsuraraTests "$@"
