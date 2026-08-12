#!/bin/sh
# ユニットテストを実行する（背景は README の Test 節を参照）。
# 判定は Package.swift と同一: DEVELOPER_DIR 環境変数 → xcode-select の実体リンクの順。
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

developer_dir="${DEVELOPER_DIR:-$(readlink /var/db/xcode_select_link 2>/dev/null || echo /Library/Developer/CommandLineTools)}"
# 末尾スラッシュを正規化してから判定する（Package.swift と同じ扱い）。
while [ "${developer_dir%/}" != "$developer_dir" ]; do developer_dir="${developer_dir%/}"; done

case "$developer_dir" in
*CommandLineTools)
    swift build --product TsuraraCoreTests
    exec "$(swift build --show-bin-path)/TsuraraCoreTests" "$@"
    ;;
*)
    exec swift test "$@"
    ;;
esac
