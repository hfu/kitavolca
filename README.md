# kitavolca

**北海道火山図パイプライン: VBM + VLCM → PMTiles**

北海道の火山基本図（VBM）と火山土地条件図（VLCM）の公開 Shapefile を、
ネイティブの GDAL/tippecanoe で再現可能に PMTiles ベクトルタイルへ変換するためのパイプラインです。

## 概要

このリポジトリが管理する対象は **生成物そのものではなくパイプライン** です。処理の流れは次の通りです。

1. **入力**: VBM / VLCM の ZIP（Shapefile）を `src/` に手動配置
2. **処理**: ネイティブ環境の GDAL/OGR・tippecanoe を使って変換
3. **出力**: 単一ファイルのベクトルタイル（`dst/vlcm.pmtiles`, `dst/vbm.pmtiles`）
4. **配布**: 生成した PMTiles はローカル成果物として扱い、Git にはコミットしない

## スコープ

- ✅ 入力 Shapefile の機械処理を自動化して PMTiles を生成
- ✅ Justfile による再現可能な実行環境（ネイティブツール前提）
- ✅ 実データ確認に基づく schema / zoom の段階的確定
- ❌ 生成 PMTiles のコミット
- ❌ 公開配布ワークフローの実装

## 使い方

### 前提

- GDAL 3.11+（`ogr2ogr` / `ogrinfo` / 統合CLIの `gdal`、PMTiles ドライバ入り）
  - ZIP 内の Shapefile 列挙に `gdal vsi list -R` を使うため、統合CLI (`gdal` コマンド) が必要
- tippecanoe（Felt メンテナンス版）
- jq
- Just（`brew install just`）
- VBM/VLCM の入力 ZIP（手動ダウンロード）

macOS/Homebrew の場合:

```bash
brew install gdal tippecanoe jq just
```

`just setup` で上記ツールの有無とバージョンを確認できます。

### 入力データの取得

対象火山の例: 樽前山（たるまえざん）、雌阿寒岳、大雪山、十勝岳、俱多楽、有珠山、北海道駒ヶ岳 ほか

- **VBM（火山基本図）**: https://web1.gsi.go.jp/bousaichiri/vbm-data_hokkai_tohoku.html
- **VLCM（火山土地条件図）**: https://www.gsi.go.jp/bousaichiri/bousaichiri41114.html

#### VBM: `just fetch-vbm` で自動取得

VBM一覧ページは静的HTMLで、火山ごとに `<a id="...">` アンカーと直後の Shapefile ZIP への直リンクを持つ構造になっているため、手動ダウンロードの代わりに以下で取得できる。

```bash
just fetch-vbm tarumae   # src/tarumae_vbm.zip として取得
just fetch-vbm meakan    # src/meakan_vbm.zip
just fetch-vbm usu       # src/usu_vbm.zip
```

`volcano_id` は一覧ページの `<a id="...">` 属性値（ページの HTML ソースで確認できる。例: `tarumae`, `meakan`, `taisetsu`, `tokachi`, `kuttara`, `usu`, `hokaikoma`）。該当する火山がまだ Shapefile 形式で提供されていない、または `volcano_id` が一覧に無い場合はエラーで終了する。

北海道地方で Shapefile が提供されている火山（2026-07-04 時点）: `atosanup`（アトサヌプリ）, `meakan`（雌阿寒岳）, `taisetsu`（大雪山）, `tokachi`（十勝岳）, `tarumae`（樽前山）, `kuttara`（俱多楽）, `usu`（有珠山）, `hokaikoma`（北海道駒ヶ岳）。`esan`（恵山）はまだ Shapefile 未提供（画像データのみ）。

#### VLCM: `just fetch-vlcm` で自動取得

VLCM一覧ページは VBM と違い、火山ごとの `<a id="...">` アンカーを持たない。代わりにダウンロードリンクのファイル名に「2桁の火山コード＋ローマ字3文字」（例: `05trm` = 樽前山）が埋め込まれており、この数字コードは VBM 側（`vbmNN`）と共通である。そのため `scripts/fetch-vlcm.sh` は volcano_id → コードの対応表を内部に持ち、コードでリンクを直接検索する。

```bash
just fetch-vlcm tarumae   # src/tarumae_vlcm.zip として取得
just fetch-vlcm usu       # src/usu_vlcm.zip
```

対応表に無い `volcano_id` を指定するとエラーになる。北海道地方で対応済みの volcano_id（2026-07-04 時点、VBM 側と ID を共通化）: `meakan`, `tokachi`, `tarumae`, `usu`, `hokaikoma`, `esan`。VBM と VLCM で提供状況が異なる点に注意（`atosanup`/`taisetsu`/`kuttara` は VLCM 未提供、逆に `esan` は VBM 未提供だが VLCM は提供されている）。未対応の火山は `scripts/fetch-vlcm.sh` 内の対応表にコードを追加すること。

### Git 運用メモ（重要）

このリポジトリでは、入力データや生成物を Git に含めない運用です。

- `src/*.zip`（手動ダウンロードした入力 ZIP）は `.gitignore` で除外
- `dst/`（PMTiles 出力）と `work/`（中間生成物）も除外
- `test_data/` 配下は生成データ（`.shp/.shx/.dbf/.prj/.geojson`）を除外し、生成スクリプトのみ管理

push 前の確認:

```bash
git status --short
git ls-files --others --exclude-standard
```

上記で意図しない大容量ファイル（ZIP/PMTiles/NDJSON など）が出ないことを確認してから push してください。

### クイックスタート

```bash
# 環境セットアップ
just setup

# 入力データ確認
just inspect

# VLCM / VBM の生成（データがある場合）
just build-vlcm &
just build-vbm &
wait

# 出力の検証
just validate

# 生成物の掃除
just clean
```

## タスク一覧（Justfile）

- `just setup` — 必須ツール（GDAL/tippecanoe/jq）の有無とバージョン確認
- `just fetch-vbm <volcano_id>` — GSI の VBM 一覧ページから Shapefile ZIP を取得し `src/` へ配置
- `just fetch-vlcm <volcano_id>` — GSI の VLCM 一覧ページから Shapefile ZIP を取得し `src/` へ配置
- `just inspect` — ZIP を展開せずに内容確認（GDAL `/vsizip/`）
- `just build-vlcm` — `dst/vlcm.pmtiles` を生成
- `just build-vbm` — `dst/vbm.pmtiles` を生成
- `just validate` — PMTiles出力の存在・可読性、中間データの属性整合性（ID番号削除・tippecanoe.layer/minzoom付与・想定外属性なし）を機械検証（異常時は exit code 1）
- `just clean` — 生成物と中間ファイルを削除
- `just serve` — `docs/` のプレビューサイトと、ローカル `dst/*.pmtiles`（`pmtiles serve`）を同時に起動。`http://localhost:8000/?source=local` で確認

## プレビューサイト（`docs/`）

`docs/index.html` + `docs/style.json` は MapLibre GL JS によるプレビューマップ。GitHub Pages で `docs/` を公開すると、本番タイル（`stars.optgeo.org` の Martin tileserver）を読み込んで表示する。

- 本番: `docs/style.json` の `sources.vbm`/`sources.vlcm` は `https://stars.optgeo.org/vbm|vlcm/{z}/{x}/{y}`（Martin の URL 規約、拡張子なし。ソース名は stars.optgeo.org 側のデプロイ設定に依存するため、変更された場合は `docs/style.json` を追従させること）
- ローカル確認: `just serve` 実行後に `?source=local` を付けてアクセスすると、`pmtiles serve dst --port 8080` が配信する `http://localhost:8080/vbm|vlcm/{z}/{x}/{y}.mvt`（`pmtiles serve` の URL 規約、`.mvt` 拡張子あり。Martin とは形式が異なるので注意）に切り替わる
- 地図クリックで、その地点の feature 属性（`分類コード`・`tippecanoe.layer` 等）をポップアップ表示

### 背景地図

- **国土地理院最適化ベクトルタイル**（`https://stars.optgeo.org/bvmap`）をベースマップとして使用。スタイルは [optimal_bvmap](https://github.com/gsi-cyberjapan/optimal_bvmap) の `style/std.json` を元に、全ての色をグレースケール化（`rgb`/`rgba`/hex を輝度ベースでモノトーン変換）
- 日本語ラベルは `localIdeographFontFamily: 'sans-serif'`（MapLibre GL JS のオプション）でブラウザのシステムフォントを使用し、GSI提供の漢字グリフPBFを個別取得しない
- **Mapterhorn**（`https://tiles.mapterhorn.com/tilejson.json`、terrarium encoding）を `terrain`・`hillshade` の両方に使用し、3D地形表示に対応（右上のコントロールでON/OFF切り替え可能）
- **シームレス空中写真**（`https://stars.optgeo.org/seamlessphoto512`）を最下層に薄く（`raster-opacity: 0.25`）配置
- レイヤ順序: 背景 → `行政区画`（陸地の白キャンバス） → 写真 → hillshade → bvmap基礎面塗り（水域・地形表記等） → **VLCM** → **VBM** → bvmap道路/建物（GSI公式`std.json`通りの交互配置） → bvmapラベル（最前面）。建物ポリゴンは道路の重要度ティアと交互に描画され、GSI公式スタイルの立体感を再現している

## レイヤ設計（MapLibre 向け）

### VLCM

- **source**: `vlcm`
- **source-layers**: `natural`, `artificial`
- 点・線・面は source-layer を分けすぎず、スタイル側で geometry-type を条件分岐

### VBM

- **source**: `vbm`
- **source-layers**: `分類コード` ごとに1レイヤ（例: `7102`, `3001`, `2101` ...）。feature 直下の `tippecanoe.layer` に分類コードを文字列化して設定し、tippecanoe が自動的にレイヤ分割する
- `docs/style.json` が各分類コードを実際の意味（道路・建物・等高線等、`docs/schema.md` 参照）ごとにグルーピングしてスタイリングしている

## Schema / Zoom 方針

属性スキーマ（保持フィールド）とズーム割当（min/max・簡略化方針）は、樽前山の実データで確定済みです。

詳細は `docs/schema.md`（保持属性・分類コードの根拠）と `docs/zoom-policy.md`（タイルサイズ実測・ズーム範囲の判断）を参照してください。

## データ利用とコンプライアンス

- VBM / VLCM は国土地理院の「基本測量成果」です
- 利用時は [国土地理院の利用規約](https://web1.gsi.go.jp/GSI/chosaku.htm) に従ってください
- 測量法第30条第1項に基づく使用承認済み: **測量法に基づく国土地理院長承認（使用）R 8JHs 207**（令和8年7月14日付、国地情使第207号。使用期間は承認後6か月間）
  - 承認条件により、成果品（本パイプラインが生成する PMTiles）には上記承認文言を明示している（`dst/*.pmtiles` の属性メタデータ、`docs/style.json` の各 source の `attribution`）
  - 承認条件(2)により、Web公開時はサイトURLを国土地理院へ報告すること

## 参考資料

- [GDAL Virtual File Systems (/vsizip/)](https://gdal.org/user/virtual_file_systems.html)
- [PMTiles specification and tooling](https://github.com/protomaps/PMTiles)
- [tippecanoe（Felt メンテナンス版）](https://github.com/felt/tippecanoe)
- [MapLibre Style Spec](https://maplibre.org/maplibre-style-spec/)

## ライセンス

CC0 1.0 Universal
