# michinori（道のり）

地図をタップして点を置くと、**点と点を徒歩ルーティングで道なりに繋ぎ、総距離（km）を常時表示する**
iPhone アプリ。ルートは端末に保存して続きから編集でき、GPX に書き出して共有シートから Zepp へ渡す。

**サーバは持たない。ルートは端末の外に出ない**（自分で GPX を共有したときだけ出る）。

- 設計: vault の `hestia/projects/michinori.md` ／ 詳細は `hestia/projects/michinori・詳細.md`

## 使い方

1. 一覧の右上「＋」で新規、または保存済みルートを選んで続きから
2. 地図をタップして点を置く。置くたびに前の点から道なりに線が伸び、上部の距離が更新される
3. 通したい道からズレたら**ピンを長押しして掴み、ドラッグ**して直す（前後2区間だけ引き直す）
4. 「戻す」で最後の点を取り消す（通信は起きない）／「全消し」で最初から
5. 「保存」で名前を付けて残す
6. 右上の共有ボタン →「Zepp にコピー」→ Active Max へ送信

⚠️ 共有シートで **Zepp は上段の横並びアイコン列**に出る（縦のリストではない）。

## 仕組み（要点だけ）

| 層 | 実装 |
|---|---|
| 地図 | `MKMapView` を `UIViewRepresentable` で包む（`Michinori/Map/MapView.swift`）。ピンのドラッグに `MKAnnotationView.isDraggable` が要るので UIKit に倒している |
| ルーティング | `SegmentRouter` プロトコル1点に閉じ込め。既定は **BRouter 公開サーバ**（`profile=hiking-mountain`）。`MapKitRouter`・`StraightLineRouter` に差し替えられる |
| 永続化 | SwiftData（`Route` / `RoutePoint` / `RouteLeg`）。⚠️ to-many の配列順序は保証されないので `order: Int` で並べ直す |
| 書き出し | GPX 1.1（`<wpt>` ＋ 1本の `<trk>`）。Douglas–Peucker で間引いてから `ShareLink` へ |

**リクエストを増やさない**: 点を足す＝1本、ドラッグ＝前後2本、undo＝0本。同じ点ペアは区間キャッシュが
覚えていて二度引かない。追加・移動には 300ms のデバウンスを入れてある。

**歩行プロファイル**は `Michinori/Routing/SegmentRouter.swift` の `RoutingProfile.current` **1箇所だけ**。
100キロウォーク用のカスタムプロファイルを brouter.de に投げたら、返ってきた `custom_…` をここへ置く。
⚠️ `trekking` は名前に反して**自転車向け**なので使わない。

**ルーティングに失敗した区間**は直線で埋め、**オレンジの破線**で描いて距離バーにも本数を出す。
GPX の `<desc>` にも書き残す（黙って混ぜない）。

## ビルドと実機インストール

`*.xcodeproj` は生成物なのでコミットしていない。`project.yml` から生成する。

```sh
brew install xcodegen   # 初回のみ

make check    # 実機なしでコンパイルだけ確かめる（署名しない・iPhone を繋がなくてよい）
make resign   # generate → build → install。iPhone を Mac に USB で繋いでから
make launch   # 実機で起動してコンソールを見る（クラッシュ調査）
make devices  # 繋がっている端末の一覧
```

- Bundle ID: `jp.kechiiiiin.michinori` ／ Team: `7Z4R4TQPZL`（無料 Apple Personal Team）
- 実機: `kechiiiiin's iPhone`（UDID は Makefile の `DEVICE`）

### 7日ごとの `make resign`

⚠️ **無料 Personal Team のプロビジョニングプロファイルは7日で失効し、失効するとアプリが起動できなくなる。**
保存したルート（SwiftData）は無事なので、再署名して開けば元通り。

| いつ | 誰 | 何を |
|---|---|---|
| 7日ごと | Keisuke | **iPhone を Mac に USB で繋ぐ。それだけ** |
| 7日ごと | ヘスティア | `cd ~/work/michinori && make resign` |

**ブラウザ作業は一度も無い。**

### 初回だけ: 開発元を信頼する

インストールした直後、最初の1回だけ iPhone 側の操作が要る。

> 設定 → 一般 → VPN とデバイス管理 → **Apple Development: kechiiiiin@gmail.com** → 信頼

## 非スコープ

標高プロファイル、GPX 読み込み、経路の自動最適化、iCloud 同期、共有・公開、住所や駅名の検索窓、
Android・iPad 対応。

## アイコン

原本は `Design/icon.svg`（深緑の背景に、生成りの破線の道と両端の点）。角丸は描かず iOS に任せる。
`Michinori/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` が生成物で、SVG を直したら `make icon` で作り直す（`brew install librsvg`）。
