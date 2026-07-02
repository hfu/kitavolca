# HANDOVER: kitavolca 設計責任者AI向け引き継ぎプロンプト

以下は、あなた（次の生成AI）がこのプロジェクトの設計責任者として引き継ぐための実行プロンプトです。 
この文書を最優先の運用指示として扱ってください。

---

## 1. あなたの役割

あなたは `kitavolca` の設計責任者AIです。目的は、
**北海道の VBM/VLCM Shapefile を Docker ベースで再現可能に PMTiles 化するパイプラインを、品質担保付きで継続進化させること**です。

以下を満たしてください。

- 技術的正確性を優先（特に tippecanoe/GDAL の仕様準拠）
- 再現性を最優先（ローカル差異で壊れない）
- 不要な大容量データを Git に含めない
- 利用者が `just` タスクだけで扱える運用を維持

---

## 2. 現在のプロジェクト状態（重要）

- リポジトリは GitHub に push 済み（`main`）
- 実装済みの主機能
  - Docker イメージで GDAL + tippecanoe を実行
  - `scripts/build-vlcm.sh` で VLCM PMTiles 生成
  - `scripts/build-vbm.sh` で VBM PMTiles 生成
  - `Justfile` から `setup/inspect/build/validate/clean` 実行可能
- VBM のメタ属性付与は、以下に修正済み
  - 誤: `properties.tippecanoe.minzoom`, `properties.tippecanoe.layer`
  - 正: feature 直下の `tippecanoe: { layer, minzoom }`
- `.gitignore` は、`src/*.zip`, `dst/`, `work/`, 生成テストデータなどを除外する方針に調整済み

---

## 3. 現在の設計方針

### 3.1 データ配置

- 入力 ZIP は `src/` 直下（手動配置）
- 出力は `dst/`
- 中間生成物は `work/`

### 3.2 VBM 変換方針

- 全 Shapefile を GeoJSON Text Sequence（NDJSON）化
- 属性整形
  - `ID番号` を削除
  - `分類コード` から `tippecanoe.layer` を設定
  - 等高線系コード（現状: `7102`, `7106`, `7133`, `7135`）に `tippecanoe.minzoom = 11`
- 最終的に tippecanoe で PMTiles 出力

### 3.3 VLCM 変換方針

- ZIP 内 .shp のファイル名から `shizen` / `jinko` を判定
- `source-layer` を `natural` / `artificial` として出力

---

## 4. 注意点・既知の論点

1. **tippecanoe メタ属性の位置**
   - 必ず feature 直下の `tippecanoe` オブジェクトに置く
   - `properties` の中には置かない

2. **文字コード・日本語属性**
   - VBM は CP932 前提の扱いが混在するため、`SHAPE_ENCODING` 指定の影響に注意
   - 日本語属性キー（例: `分類コード`）を jq で扱う場合はキー参照を慎重に行う

3. **Git 運用**
   - ZIP, PMTiles, NDJSON, 生成 Shapefile をコミットしない
   - コミット前に以下を実行
     - `git status --short`
     - `git ls-files --others --exclude-standard`

4. **性能・サイズ**
   - タイルサイズ警告（`>500000`）は現状出る場合がある
   - 必要ならズーム戦略・簡略化パラメータを見直す

---

## 5. 次の優先タスク（推奨順）

1. **仕様ドキュメント確定**
   - `docs/schema.md` と `docs/zoom-policy.md` の TBD を実測に基づき確定

2. **VBM 分類コード運用の明文化**
   - 等高線対象コードの根拠（データ確認結果）を README または docs に整理

3. **検証導線の改善**
   - `just validate` を強化し、
     - 出力ファイル存在
     - 代表 feature に `tippecanoe.layer/minzoom` が存在
     - 想定外属性の混入なし
     を機械検証可能にする

4. **失敗時のデバッグ容易化**
   - `scripts/build-vbm.sh` のエラーメッセージを、どの段階で失敗したか分かる粒度に改善

---

## 6. 受け入れ基準（あなたの変更の Done 条件）

- `just setup` が成功
- `just build-vlcm` / `just build-vbm` が成功
- 出力 PMTiles が生成される
- VBM 中間 NDJSONで、等高線系 feature が top-level `tippecanoe.minzoom=11` を持つ
- `.gitignore` で大容量生成物が未追跡に保たれる
- README / docs が実装と矛盾しない

---

## 7. 参考ファイル（最初に読む）

- `README.md`
- `Justfile`
- `scripts/build-vbm.sh`
- `scripts/build-vlcm.sh`
- `docs/schema.md`
- `docs/zoom-policy.md`

---

## 8. 最初の実行コマンド

```bash
just setup
just inspect
just build-vlcm
just build-vbm
just validate
```

必要に応じて:

```bash
just clean
```

---

## 9. 最後の指示

- 変更は常に「再現性」「仕様準拠」「不要データ非コミット」を優先
- 不確実な点は、推測で固定せず、検証コマンドとセットで判断
- 提案だけで終わらず、可能な限り実装・検証・ドキュメント反映まで完了させること
