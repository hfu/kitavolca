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
- **2026-07-04: `src/` への VBM 入力データ取得を自動化した**
  - `scripts/fetch-vbm.sh` + `just fetch-vbm <volcano_id>` で、GSI の VBM 一覧ページ（`web1.gsi.go.jp/bousaichiri/vbm-data_hokkai_tohoku.html`、静的HTML、`<a id="...">` アンカー + 直後の `*-shp.zip` 直リンクという構造）から Shapefile ZIP を直接ダウンロードし `src/<volcano_id>_vbm.zip` に配置する
  - `meakan`（雌阿寒岳）・`usu`（有珠山）・`hokaikoma`（北海道駒ヶ岳）で実際に取得 → `build-vbm.sh` まで通ることを確認済み
  - 実装上の注意: 数百KBの一覧ページを `curl` で丸ごとシェル変数に読み込み `printf '%s' "$var" | grep ...` のようにパイプで渡すと、環境（特にサンドボックス化されたシェル）によっては正しく読み取れないことがある。一覧ページは一時ファイルに保存し、`grep`/`awk` にはファイル引数で渡す方式にした方が確実
- **2026-07-04: `src/` への VLCM 入力データ取得も自動化した**
  - 正しい一覧ページは `www.gsi.go.jp/bousaichiri/bousaichiri41114.html`（HANDOVER/READMEに以前記載していた `web2.gsi.go.jp/bousaichiri/volcano-maps-vlcm-data.html` は汎用ナビゲーションページで実データなし。ユーザー指摘により判明）
  - この一覧ページは VBM と構造が異なり、火山ごとの `<a id="...">` アンカーが無い。代わりにダウンロードリンクのファイル名に埋め込まれた「2桁の火山コード＋ローマ字3文字」（例: `05trm`=樽前山）で判別する。この数字コードは VBM 側の `vbmNN` と共通（例: vbm05=樽前山=vlcm05）
  - `scripts/fetch-vlcm.sh` + `just fetch-vlcm <volcano_id>` を実装。volcano_id → コードの対応表をスクリプト内の `case` 文で保持（bash 3.2 系の macOS 標準シェルは連想配列 `declare -A` 非対応のため、あえて `case` 文にしている）
  - `tarumae` で取得 → 既存の手動ダウンロード分と **MD5 完全一致** を確認。`usu` でも新規取得 → `build-vlcm.sh` まで通ることを確認済み
  - VBM と VLCM で提供している火山が完全には一致しないことが判明: `atosanup`/`taisetsu`/`kuttara` は VLCM 未提供、逆に `esan` は VBM 未提供だが VLCM は提供されている（対応表は README 参照）
- **2026-07-04: `build-vbm.sh`/`build-vlcm.sh` を複数火山対応に一般化した**
  - 旧実装は `tarumae_vbm.zip`/`tarumae_vlcm.zip` が存在すればそれだけを特別扱いする一時的なテスト用ハードコードが残っていた。`src/*_vbm.zip` / `src/*_vlcm.zip` という命名規約ベースの glob に統一し、`src/` にある全ての実データ ZIP をまとめて処理するようにした（`vbm_test.zip`/`vlcm_test.zip` のような単体テスト用フィクスチャは命名規約が違うため自然に除外される）
  - tippecanoe のメタデータ名も `Tarumaezan VBM/VLCM` → `Hokkaido VBM/VLCM`（`-N` も `kitavolca-vbm/vlcm`）に変更
  - `just fetch-vbm usu` で有珠山データを実際に取得し、樽前山と結合してビルド → タイルサイズ警告は変化なし（同じ5タイルのみ、樽前山エリア）。※この結論は後述の8火山結合検証で覆った
  - 同じ検証で水深系分類コード（7132-7134）の根拠確認も試みたが、有珠山の VBM Shapefile には等高線・等深線系のファイル自体が含まれておらず未解決のまま（詳細は `docs/schema.md`）
- **2026-07-04: 北海道地方の VBM Shapefile 提供済み全8火山（アトサヌプリ・雌阿寒岳・大雪山・十勝岳・樽前山・俱多楽・有珠山・北海道駒ヶ岳）を結合し再検証**
  - 549,748 features に到達。**タイルサイズ警告が 5→14 件に増加**（ズーム6・8にも新規発生）。2火山結合時の「悪化しない」という結論は覆った——少数サンプルで一般化しすぎないこと
  - 対策として一時的に `--drop-densest-as-needed` を `build-vbm.sh`/`build-vlcm.sh` に追加し、`pmtiles tile <path> <z> <x> <y> | wc -c` で実測して「全タイル500KB未満」と判断した——**が、これは誤りだった**。`pmtiles tile` はPMTilesに格納された**圧縮後**のバイト数を返すが、tippecanoeの`>500000`警告は**非圧縮**サイズを指しており、比較する指標を間違えていた（`gunzip`して確認すると実際は1.2〜1.6MBあった）
  - **2026-07-04（同日中に修正）: ユーザーが大雪山エリアで等高線の大量ドロップを目視で発見** → `--drop-densest-as-needed`はどの feature が失われるか制御できずデータ欠損を生むため不適切と判断。`tippecanoe-decode`でタイル内訳を確認し、`7101`/`7102`(等高線)がバイト数の大半を占めることを確認
  - **対策を全面的に変更**: `--drop-densest-as-needed`を完全撤去し、代わりに等高線・等深線系8コード全て（`7101/7102/7105/7106/7132/7133/7134/7135`）の`minzoom`を11→12に統一（データ欠損なし。旧実装は4コードのみminzoom=11、残り4コードは無制限という不整合があったのも解消）
  - 結果: 大雪山エリアの警告タイル(旧z11で7件)は全て解消。樽前山エリアに残った4タイルは**等高線と無関係**な別コード（`2101`/`2106`/`5101`/`5102`、当初は正体未特定）が原因と判明
  - **同日中に正体を特定・解決**: 樽前山のシェープファイルを1つずつ変換して確認した結果、`2101/2103/2106/2107`=**道路**、`5101/5102/5106`=**水涯線・海岸線**と判明（`3001`等=建物も含め、由来ファイル名との対応表を`docs/schema.md`に整理）。ユーザー指示で[国土地理院最適化ベクトルタイル](https://github.com/gsi-cyberjapan/optimal_bvmap)の設計を参考にしつつ（建物の面積間引きのような作り込みはしない方針）、道路・建物にも同じ単純な`minzoom`シフトを適用。最終的に等高線・道路・建物の計16コードを**minzoom=13**に統一（12では樽前山火口周辺の1タイルのみ非圧縮556KBで超過が残ったため、13まで追加シフト）。海岸線はGSIの設計に倣い意図的に制限しないまま
  - 最終確認: 北海道8火山結合データ・過去に警告が出た全13候補タイルを`pmtiles tile | gunzip -c | wc -c`で実測し、**全て500KB未満（最大472,270 bytes）を確認**。データ間引きは一切無し（549,748 features のまま不変）。VBM PMTilesは59MB（低ズームでの重複描画が減り80-96MBから縮小）
  - 教訓: タイルサイズ検証では`pmtiles tile | gunzip -c | wc -c`で非圧縮サイズを見ること。圧縮後のバイト数と比較すると実態を見誤る。さらに、`--drop-densest-as-needed`を使わない場合でも、tippecanoeのビルドログが「警告0件」でも実際には超過しているケースがあった（12/3658/1510の例）——**ログを信用せず、必ず実測すること**
- **2026-07-05: MapLibreプレビューサイト（`docs/index.html` + `docs/style.json`）を追加**
  - ユーザーが生成PMTilesを`stars.optgeo.org`（Martin tileserver）にアップロードする運用のため、それを前提としたプレビューサイトを`docs/`（GitHub Pages公開想定）に構築
  - 本番タイルURL規約はMartin方式（`https://stars.optgeo.org/kitavolca-vbm|vlcm/{z}/{x}/{y}`、拡張子なし）。ローカル確認は`just serve`（`pmtiles serve dst --port 8080` + `docs/`を`python3 -m http.server 8000`で配信）で、`pmtiles serve`のURL規約（`.mvt`拡張子あり）に切り替わる。**2つのツールでURL形式が違う**ことに注意
  - スタイルは`docs/schema.md`で特定した分類コードの実際の意味（道路・建物・等高線・海岸線等）ごとにグルーピング。国土地理院最適化ベクトルタイル（[optimal_bvmap](https://github.com/gsi-cyberjapan/optimal_bvmap)）の実データ（`https://stars.optgeo.org/bvmap` のTileJSON）から実際のレイヤー別minzoom設計（道路z4・建物z14・等高線z9・海岸線z4等）を確認し参考にした
  - Playwright（`npx playwright install chromium`、実行はスクラッチディレクトリで）でヘッドレスブラウザ検証済み: GSI標準地図と重ねた表示、VLCM featureクリックでの属性ポップアップ（`natural`レイヤー、`name=溶岩円頂丘`等）、高ズームでの等高線・建物・道路描画（minzoom=13が正しく機能）を確認。コンソールエラーなし
- 実装済みの主機能
  - `scripts/fetch-vbm.sh` で VBM 入力データ（Shapefile ZIP）を GSI から取得
  - `scripts/build-vlcm.sh` で VLCM PMTiles 生成（`src/*_vlcm.zip` を結合処理）
  - `scripts/build-vbm.sh` で VBM PMTiles 生成（`src/*_vbm.zip` を結合処理）
  - `docs/index.html`/`docs/style.json` で MapLibre プレビュー（本番/ローカル両対応）
  - `Justfile` から `setup/fetch-vbm/fetch-vlcm/inspect/build/validate/serve/clean` 実行可能
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
- `scripts/fetch-vbm.sh`
- `scripts/fetch-vlcm.sh`
- `scripts/build-vbm.sh`
- `scripts/build-vlcm.sh`
- `docs/schema.md`
- `docs/zoom-policy.md`
- `docs/index.html`, `docs/style.json`（MapLibre プレビューサイト）

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
