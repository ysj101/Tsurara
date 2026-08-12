#!/bin/sh
# build/Tsurara.app を組み立てる。
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

swift build -c release --product Tsurara
BIN_DIR=$(swift build -c release --show-bin-path)
APP_DIR="build/Tsurara.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_DIR/Tsurara" "$APP_DIR/Contents/MacOS/Tsurara"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# バージョンは TsuraraCore.version を単一の情報源とし、バンドルへ反映する。
VERSION=$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/TsuraraCore/TsuraraCore.swift)
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"

# SMAppService（ログイン時起動）はバンドル全体の署名を要求するため、
# 手動ビルドでは ad-hoc 署名を付与する。
codesign --force --sign - "$APP_DIR"

echo "Created $APP_DIR (version $VERSION)"
