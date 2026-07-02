# Zoom Policy

**実データ（樽前山 VBM/VLCM）に基づき確定。** 測定コマンドと結果は各節に記載。

## 現状の設定

- `scripts/build-vbm.sh`: `tippecanoe --force -P -n "Tarumaezan VBM" ... -Z 5 -z 14`
- `scripts/build-vlcm.sh`: `tippecanoe --force -P ... -Z 5 -z 14 -L natural:... -L artificial:...`

`-Z 5`（最小ズーム5）〜`-z 14`（最大ズーム14）で両方とも共通。`-P`（並列読み込み）以外の簡略化オプションは未指定＝tippecanoe のデフォルト挙動（`--drop-densest-as-needed` などは未使用）。

## 実測結果

### VLCM: 警告なし

`work/vlcm/natural.ndjson` + `work/vlcm/artificial.ndjson`（計 1,594 features, 639,449 bytes）でローカル tippecanoe（v2.79.0）を実行 → タイルサイズ警告は **0件**。データ量が小さく、現状の `-Z 5 -z 14` のままで問題ない。

### VBM: ズーム 9〜12 で 5 タイルが 500KB 超過

`work/vbm/vbm_filtered.ndjson`（201,939 features, 71,124,591 bytes）でローカル tippecanoe を実行し再現:

```bash
tippecanoe --force -P -n "Tarumaezan VBM" -A "GSI" -N "tarumaezan-vbm" -Z 5 -z 14 -o /tmp/vbm_test.pmtiles work/vbm/vbm_filtered.ndjson
```

出力された警告（すべて `>500000` bytes、tippecanoe のデフォルト上限）:

| タイル (z/x/y) | サイズ (bytes) | 上限超過率 |
|---|---|---|
| 9/457/188 | 563,814 | +12.8% |
| 10/914/377 | 732,539 | +46.5% |
| 11/1829/755 | 673,527 | +34.7% |
| 11/1828/755 | 726,278 | +45.3% |
| 12/3658/1510 | 562,430 | +12.5% |

いずれも樽前山中心部と同じ座標域（`457/188` 系列はズームが上がるごとに `914/377`→`1828-1829/755`→`3656-3660/1508-1511` と同一地点にズームインした先）。原因は、VBM の全 63 種類の `分類コード` を単一の tippecanoe レイヤ（`-L` 未指定のためファイル名由来の1レイヤ）にまとめて詰め込んでいるため、中〜高密度ズームで等高線(3001 Polygon 112,444件 / 2101,2106 LineString 合計45,000件超）が同一タイルに集中すること。

### 現時点の判断

- **単一火山（樽前山）のテストデータでは許容範囲**: 超過は最大+46.5%で、いずれも致命的な破損ではなく tippecanoe の警告レベル。実運用（複数火山の結合）でデータ量が増えると悪化する可能性が高い
- **今は zoom 範囲・簡略化パラメータを変更しない**: 単一火山データのみでチューニングすると、複数火山を結合した際の挙動を見誤る恐れがある。複数火山のデータを追加した時点で再測定し、必要なら以下の対策を検討する:
  - VBM も VLCM 同様に `分類コード` のグループ（等高線系・行政界系・注記系など）ごとに `-L` でレイヤを分割する
  - `--drop-densest-as-needed` または `-al`（自動簡略化）を有効化する
  - 低ズーム（5〜8程度）では注記・水準点などの点データを間引く（`-r`/`-B` の調整）

## VBM/VLCM 共通の再測定手順

新しい火山データを追加した後、または本番相当のデータ量になった時点で、以下を再実行してタイルサイズ警告を確認すること。

```bash
just build-vbm 2>&1 | grep -E "size is.*>500000"
just build-vlcm 2>&1 | grep -E "size is.*>500000"
```

警告が増加・悪化した場合は、上記「現時点の判断」の対策リストから着手する。

## References

- [tippecanoe zoom parameter documentation](https://github.com/felt/tippecanoe)
- [PMTiles specification (zoom encoding)](https://github.com/protomaps/PMTiles)
- Web Mercator projection and typical zoom levels: https://wiki.openstreetmap.org/wiki/Zoom_levels
