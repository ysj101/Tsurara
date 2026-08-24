#!/bin/sh
# コード署名用の自己署名証明書をログインキーチェーンへ用意する。
#
# ad-hoc 署名の designated requirement は cdhash だけで構成されるため、再ビルドの
# たびに TCC からは別アプリと見なされ、アクセシビリティと画面収録の許可がやり直しに
# なる。安定した署名 ID で署名すれば、許可は再ビルドをまたいで保持される。
#
# 証明書は PC ごとに用意する。TCC のデータベース自体が PC ごとに独立しているため、
# 全機で同じ証明書を共有する必要はなく、秘密鍵を持ち回らずに済む。
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

SIGN_IDENTITY=${TSURARA_SIGN_IDENTITY:-Tsurara Dev}
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
VALIDITY_DAYS=3650

if security find-identity -v -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
    echo "署名 ID \"$SIGN_IDENTITY\" は既に使える。何もしない。"
    exit 0
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# codesign は Code Signing の EKU を持つ証明書だけを identity として扱う。
# Homebrew に依存しないよう、macOS 同梱の /usr/bin/openssl を使う。
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" \
    -days "$VALIDITY_DAYS" -subj "/CN=$SIGN_IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:true" 2>/dev/null

# PKCS12 は空パスフレーズだと security import の MAC 検証に失敗するため、
# 秘密鍵と証明書を PEM のまま個別に取り込む。
# -T /usr/bin/codesign で、codesign だけに鍵の利用を許可する。
security import "$WORK_DIR/key.pem" -k "$KEYCHAIN" -T /usr/bin/codesign
security import "$WORK_DIR/cert.pem" -k "$KEYCHAIN" -T /usr/bin/codesign

# 自己署名ルートは信頼設定を入れるまで identity として扱われない。
# 管理者パスワードの入力を求められる。
echo "コード署名用の信頼設定を追加する。パスワードの入力を求められる。"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK_DIR/cert.pem"

if ! security find-identity -v -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
    echo "error: 署名 ID \"$SIGN_IDENTITY\" を用意できなかった" >&2
    exit 1
fi

echo "署名 ID \"$SIGN_IDENTITY\" を用意した。"
echo "既存の許可は古い署名に紐づくため、次を実行してから許可し直す:"
echo "  tccutil reset Accessibility com.ysj.Tsurara"
echo "  tccutil reset ScreenCapture com.ysj.Tsurara"
