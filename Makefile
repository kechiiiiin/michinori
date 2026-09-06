# michinori — 実機まわりの手順を1コマンドに畳んだもの
#
# 何のためか:
#   無料の Apple Personal Team で署名したプロビジョニングプロファイルは **7日で失効**し、
#   失効するとアプリが起動できなくなる（保存したルートは無事。再署名して開けば元通り）。
#   その復旧が `xcodegen generate` → `xcodebuild` → `devicectl install` の3手だったので、
#   `make resign` の1手にした。詳細は README.md「ビルドと実機インストール」。
#
# よく使うのは:
#   make resign    7日ごとの再署名。iPhone を Mac に繋いでから叩く
#   make check     実機なしでコンパイルだけ確かめる（署名しない・繋がなくてよい）
#   make launch    実機で起動してコンソールを見る（クラッシュ調査）
#   make icon      Design/icon.svg からアプリアイコン PNG を再生成する（rsvg-convert が要る）
#   make devices   繋がっている端末の一覧（DEVICE の UUID を確かめたいとき）
#
# ⚠️ 注意
#   - `*.xcodeproj` は生成物でコミットしていない。**必ず `xcodegen generate` が先**
#     （`brew install xcodegen` が要る）。各ターゲットの先頭で毎回走らせている
#   - `-derivedDataPath build` は**実機インストール用の成果物**。`make check` はこれを壊さないよう
#     `build-check` を別に使い、終わったら消している
#   - 初回インストール時だけ、実機で開発元を信頼する操作が要る
#     （設定 → 一般 → VPN とデバイス管理 → Apple Development: kechiiiiin@gmail.com → 信頼）

DEVICE  = 8EAC2623-47F0-58AC-9DEF-8DD9AE4D6E55
BUNDLE  = jp.kechiiiiin.michinori
PROJECT = michinori.xcodeproj
SCHEME  = Michinori
APP     = build/Build/Products/Debug-iphoneos/michinori.app

.PHONY: icon help resign generate build install launch check devices clean

help:
	@echo "resign     再署名（generate → build → install）。7日ごと・iPhone を繋いでから"
	@echo "check      実機なしでコンパイルだけ確認（署名なし）"
	@echo "launch     実機で起動してコンソールを見る"
	@echo "icon            Design/icon.svg からアイコン PNG を再生成"
	@echo "devices    繋がっている端末の一覧"
	@echo "clean      build/ build-check/ と生成した .xcodeproj を消す"

## 7日ごとの再署名。これ1本で generate → build → install まで通る
resign: generate build install
	@echo "✅ 再署名して実機に入れた。次の失効まで7日"

generate:
	xcodegen generate

## 実機向けにビルドして署名する（プロファイルの更新も任せる）
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination "id=$(DEVICE)" -configuration Debug \
	  -derivedDataPath build -allowProvisioningUpdates build

install:
	xcrun devicectl device install app --device $(DEVICE) $(APP)

## 実機で起動してコンソールを見る（クラッシュしていないかの確認）
launch:
	xcrun devicectl device process launch --device $(DEVICE) --console \
	  --terminate-existing $(BUNDLE)

## 実機を繋がずにコンパイルだけ確かめる。署名もしないので手ぶらで叩ける
## ⚠️ build/ とは別の build-check/ を使う（実機インストール用の成果物を壊さないため）
check: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'generic/platform=iOS' -configuration Debug \
	  -derivedDataPath build-check CODE_SIGNING_ALLOWED=NO build
	@rm -rf build-check
	@echo "✅ コンパイルは通る"

icon:
	rsvg-convert -w 1024 -h 1024 Design/icon.svg -o Michinori/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
	@echo "✅ アイコン PNG を再生成した"

devices:
	xcrun devicectl list devices

clean:
	rm -rf build build-check $(PROJECT)
