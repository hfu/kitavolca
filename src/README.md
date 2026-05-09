# 入力データ置き場（src/）

このディレクトリは、手動で取得した入力 ZIP を置くための **フラットなステージング領域** です。

## 配置ルール

- ZIP は **サブディレクトリを作らず** 直下に配置
- 基本は GDAL `/vsizip/` で非展開のまま参照
- ネットワーク制約のある環境でも扱いやすい運用を優先

## 想定ファイル

### VBM（火山基本図）

北海道の各火山に対応する Shapefile ZIP（例）:
- `tarumae_vbm.zip`
- `meakan_vbm.zip`
- `daisetsu_vbm.zip`

取得元: https://web1.gsi.go.jp/bousaichiri/vbm-data_hokkai_tohoku.html

### VLCM（火山土地条件図）

火山地形分類の Shapefile ZIP（例）:
- `tarumae_vlcm.zip`
- 地域単位・火山単位の各 ZIP

取得元: https://web2.gsi.go.jp/bousaichiri/volcano-maps-vlcm-data.html

## 補足

- **再現性**: 同じ入力ファイルで繰り返し実行可能
- **コミット禁止**: 入力 ZIP はローカル運用が前提（Git 管理しない）
- **文字コード注意**: 一部 Shapefile の属性/パスは CP932（Shift_JIS）前提。変換時に対応済み
- **名称方針**: 火山名は公式表記・公式読みを優先（例: 樽前山「たるまえざん」）
