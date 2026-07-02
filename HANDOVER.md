# HANDOVER: kitavolca 設計責任者AI向け引き継ぎプロンプト

以下は、あなた（次の生成AI）がこのプロジェクトの設計責任者として引き継ぐための実行プロンプトです。 
この文書を最優先の運用指示として扱ってください。

---

## 1. あなたの役割

あなたは `kitavolca` の設計責任者AIです。目的は、
**北海道の VBM/VLCM Shapefile をネイティブ GDAL/tippecanoe で再現可能に PMTiles 化するパイプラインを、品質担保付きで継続進化させること**です。

以下を満たしてください。

- 技術的正確性を優先（特に tippecanoe/GDAL の仕様準拠）
- 再現性を最優先（ローカル差異で壊れない）
- 不要な大容量データを Git に含めない
- 利用者が `just` タスクだけで扱える運用を維持

---

## 2. 現在のプロジェクト状態（重要）

- リポジトリは GitHub に push 済み（`main`）
- **2026-07-03: Docker ベースの実行方式を廃止し、ネイティブ実行に一本化した**
  - 理由: Docker daemon が起動していない環境でも Homebrew 版の GDAL/tippecanoe/jq がすでに動作しており、「Docker で再現性を担保する」という前提が実態と合っていなかった（中途半端な二重運用はかえって信頼性を損なう）
  - `Dockerfile` は削除。`scripts/build-vbm.sh` / `scripts/build-vlcm.sh` / `Justfile` はすべて `docker run` を使わず、PATH 上の `ogr2ogr`/`ogrinfo`/`tippecanoe`/`jq` を直接呼び出す
  - 前提ツールのバージョン固定は brew の formula 任せ（厳密なピン留めは未実装。必要になれば検討）
- 実装済みの主機能
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

1. ~~**仕様ドキュメント確定**~~ — 完了（2026-07-03）
   - `docs/schema.md`: 分類コードごとの属性形状・保持属性・分類コード分布を実測して確定
   - `docs/zoom-policy.md`: タイルサイズ警告（VBM z9-12で5タイルが500KB超過、VLCMは警告なし）を実測して記載

2. ~~**VBM 分類コード運用の明文化**~~ — 完了（2026-07-03）
   - 標高値の実測（25の倍数の出現率）により、`7101/7105`（計曲線=間引き済み強調線）と `7102/7106`（主曲線=密な通常線）のペア構造を確認。`minzoom=11` は各ペアの密度が高い側（主曲線）にのみ付与されており合理的と判断
   - 水深系（`7132/7133/7134`）は同型のペア構造が疑われるが、樽前山データでは該当件数が少なすぎ（合計25件）て未確定のまま。詳細は `docs/schema.md` 参照

3. ~~**検証導線の改善**~~ — 完了（2026-07-03）
   - `just validate` を機械検証に強化: (1) PMTiles の存在・GDALでの可読性、(2) VBM中間データの ID番号削除済み・tippecanoe.layer付与・等高線コードのminzoom=11付与、(3) VBM/VLCM中間データの想定外属性キー混入なし、を自動チェックし、エラー時は exit code 1 で失敗する
   - 意図的に破損させたデータ（ID番号残存・minzoom欠落・未知属性混入）で検出できることを確認済み
   - `work/` が無い場合（`just clean` 後など）は中間データ検証を warning でスキップし、ファイル存在チェックのみ行う

4. ~~**失敗時のデバッグ容易化**~~ — 完了（2026-07-03）
   - `scripts/build-vbm.sh`: 各段階に `[1. ZIP検出/ZIP列挙/ogr2ogr変換]`, `[2. 結合/jqフィルタリング]`, `[3. tippecanoe]` のタグを付与。特に旧実装で `ogr2ogr ... 2>/dev/null || true` によりシェープファイル単位の変換失敗を握りつぶしていた箇所を修正し、失敗したファイル名とエラー内容を表示した上で exit 1 するようにした
   - `scripts/build-vlcm.sh` も同様に段階タグを追加し、`ogr2ogr`/`gdal vsi list`/`tippecanoe` の失敗時にどのファイル・どの段階かが分かるようにした
   - ZIP不在・破損ZIPの2パターンで実際にエラーメッセージが段階付きで表示されることを確認済み。正常系（樽前山データ）は同じ件数で再現できることも確認済み

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
