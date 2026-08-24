# Tsurara 開発用タスク
#
#   make test   ユニットテストを実行（Scripts/test.sh）
#   make build  デバッグビルド（全ターゲット）
#   make app    リリースビルドして build/Tsurara.app を生成（Scripts/make-app.sh）
#   make signing コード署名用の証明書を用意（Scripts/setup-signing.sh）
#   make run    app を生成して起動
#   make stop   起動中の Tsurara を終了
#   make clean  ビルド成果物を削除

.PHONY: test build app run stop clean signing

test:
	Scripts/test.sh

build:
	swift build

app:
	Scripts/make-app.sh

signing:
	Scripts/setup-signing.sh

# open は起動中のアプリがあると再起動せず既存プロセスを前面に出すだけなので、
# 新しいビルドを確実に反映させるため先に終了させる。
run: app stop
	open build/Tsurara.app

stop:
	-killall Tsurara

clean:
	rm -rf .build build
