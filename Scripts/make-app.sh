#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(dirname -- "$SCRIPT_DIR")

cd "$REPOSITORY_ROOT"

swift build -c release --product Tsurara
BIN_DIR="$REPOSITORY_ROOT/.build/release"
APP_DIR="$REPOSITORY_ROOT/build/Tsurara.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_DIR/Tsurara" "$APP_DIR/Contents/MacOS/Tsurara"
cp "$REPOSITORY_ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# SMAppService（ログイン時起動）はバンドル全体の署名を要求するため、
# 手動ビルドでは ad-hoc 署名を付与する。
codesign --force --sign - "$APP_DIR"

echo "Created $APP_DIR"
