# kitavolca

**北海道火山図パイプライン: VBM + VLCM → PMTiles**

北海道の火山基本図（VBM）と火山土地条件図（VLCM）の公開 Shapefile を、
Docker ベースで再現可能に PMTiles ベクトルタイルへ変換するためのパイプラインです。

## 概要

このリポジトリが管理する対象は **生成物そのものではなくパイプライン** です。処理の流れは次の通りです。

1. **入力**: VBM / VLCM の ZIP（Shapefile）を `src/` に手動配置
2. **処理**: Docker 上で GDAL/OGR・tippecanoe を使って変換
3. **出力**: 単一ファイルのベクトルタイル（`dst/vlcm.pmtiles`, `dst/vbm.pmtiles`）
4. **配布**: 生成した PMTiles はローカル成果物として扱い、Git にはコミットしない

## スコープ

- ✅ 入力 Shapefile の機械処理を自動化して PMTiles を生成
- ✅ Docker + Justfile による再現可能な実行環境
- ✅ 実データ確認に基づく schema / zoom の段階的確定
- ❌ 生成 PMTiles のコミット
- ❌ 公開配布ワークフローの実装

## 使い方

### 前提

- Docker
- Just（`brew install just`）
- VBM/VLCM の入力 ZIP（手動ダウンロード）

### 入力データの取得

対象火山の例: 樽前山（たるまえざん）、雌阿寒岳、大雪山、十勝岳、俱多楽、有珠山、北海道駒ヶ岳 ほか

- **VBM（火山基本図）**: https://web1.gsi.go.jp/bousaichiri/vbm-data_hokkai_tohoku.html
- **VLCM（火山土地条件図）**: https://web2.gsi.go.jp/bousaichiri/volcano-maps-vlcm-data.html

1. Shapefile ZIP をダウンロード
2. `src/` ディレクトリ直下へ配置（フラット構成）

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

- `just setup` — Docker イメージ構築とツール確認
- `just inspect` — ZIP を展開せずに内容確認（GDAL `/vsizip/`）
- `just build-vlcm` — `dst/vlcm.pmtiles` を生成
- `just build-vbm` — `dst/vbm.pmtiles` を生成
- `just validate` — 出力ファイル存在と簡易確認
- `just clean` — 生成物と中間ファイルを削除

## レイヤ設計（MapLibre 向け）

### VLCM

- **source**: `vlcm`
- **source-layers**: `natural`, `artificial`
- 点・線・面は source-layer を分けすぎず、スタイル側で geometry-type を条件分岐

### VBM

- **source**: `vbm`
- **source-layers**: 実データ確認後に最小粒度で決定

## Schema / Zoom 方針

属性スキーマ（保持フィールド）とズーム割当（min/max・簡略化方針）は **TBD** です。
実データを確認しながら段階的に決定します。

詳細は `docs/schema.md` と `docs/zoom-policy.md` を参照してください。

## データ利用とコンプライアンス

- VBM / VLCM は国土地理院の「基本測量成果」です
- 利用時は [国土地理院の利用規約](https://web1.gsi.go.jp/GSI/chosaku.htm) に従ってください
- 公開配布時には必要な手続き・確認を行ってください

## 参考資料

- [GDAL Virtual File Systems (/vsizip/)](https://gdal.org/user/virtual_file_systems.html)
- [PMTiles specification and tooling](https://github.com/protomaps/PMTiles)
- [tippecanoe（Felt メンテナンス版）](https://github.com/felt/tippecanoe)
- [MapLibre Style Spec](https://maplibre.org/maplibre-style-spec/)

## ライセンス

CC0 1.0 Universal
