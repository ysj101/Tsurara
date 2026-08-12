#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(dirname -- "$SCRIPT_DIR")

cd "$REPOSITORY_ROOT"

export CLANG_MODULE_CACHE_PATH="$REPOSITORY_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$REPOSITORY_ROOT/.build/swiftpm-module-cache"

swift build -c release --product Tsurara --disable-sandbox
BIN_DIR=$(swift build -c release --show-bin-path --disable-sandbox)
APP_DIR="$REPOSITORY_ROOT/build/Tsurara.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_DIR/Tsurara" "$APP_DIR/Contents/MacOS/Tsurara"
cp "$REPOSITORY_ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "Created $APP_DIR"
