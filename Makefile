# Tsurara 開発用タスク
#
#   make test   ユニットテストを実行（Scripts/test.sh）
#   make build  デバッグビルド（全ターゲット）
#   make app    リリースビルドして build/Tsurara.app を生成（Scripts/make-app.sh）
#   make run    app を生成して起動
#   make stop   起動中の Tsurara を終了
#   make clean  ビルド成果物を削除

.PHONY: test build app run stop clean

test:
	Scripts/test.sh

build:
	swift build

app:
	Scripts/make-app.sh

run: app
	open build/Tsurara.app

stop:
	-killall Tsurara

clean:
	rm -rf .build build
