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
VERSION=$(sed -n 's/.*version[^=]*= *"\([^"]*\)".*/\1/p' Sources/TsuraraCore/TsuraraCore.swift)
if [ -z "$VERSION" ]; then
    echo "error: TsuraraCore.version を抽出できなかった" >&2
    exit 1
fi
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"

# SMAppService（ログイン時起動）はバンドル全体の署名を要求するため、
# 手動ビルドでも署名を付与する。
#
# ad-hoc 署名の designated requirement は cdhash だけで構成されるため、再ビルドの
# たびに TCC からは別アプリと見なされ、アクセシビリティと画面収録の許可が失われる。
# 安定した署名 ID があれば、それで署名して許可を再ビルドをまたいで保持する。
SIGN_IDENTITY=${TSURARA_SIGN_IDENTITY:-Tsurara Dev}
if security find-identity -v -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    echo "warning: 署名 ID \"$SIGN_IDENTITY\" が見つからないため ad-hoc 署名する。" >&2
    echo "warning: 再ビルドのたびにシステム設定での許可をやり直す必要がある。" >&2
    codesign --force --sign - "$APP_DIR"
fi

echo "Created $APP_DIR (version $VERSION)"
