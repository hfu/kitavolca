#!/bin/bash
# build-vbm.sh — VBM の ZIP 内 Shapefile から PMTiles を生成
# 分類コードベースでフィルタリングし、等高線系コードに minzoom=11 を適用
# ネイティブ実行（GDAL/jq/tippecanoe が PATH にあること）を前提とする

set -euo pipefail

WORKSPACE_DIR="${1:-.}"
INPUT_DIR="${WORKSPACE_DIR}/src"
WORK_DIR="${WORKSPACE_DIR}/work/vbm"
OUTPUT_FILE="${WORKSPACE_DIR}/dst/vbm.pmtiles"

echo "=== VBM PMTiles 生成 ==="
echo ""

for cmd in ogr2ogr gdal jq tippecanoe; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "❌ [事前チェック] '$cmd' が見つかりません。'just setup' で必要ツールを確認してください"; exit 1; }
done

mkdir -p "$WORK_DIR" "${WORKSPACE_DIR}/dst"
rm -f "$WORK_DIR"/*.ndjson 2>/dev/null || true

vbm_zip_list="$(ls "$INPUT_DIR"/*_vbm.zip 2>/dev/null || true)"
if [ -z "$vbm_zip_list" ]; then
    echo "❌ [1. ZIP検出] VBM の ZIP（*_vbm.zip）が ${INPUT_DIR} に見つかりません"
    exit 1
fi

echo "1. ZIP から VBM レイヤを抽出・変換中..."

# ZIP 内パスは CP932 由来で日本語ディレクトリ名を含むため、実ファイルとして
# 展開せず GDAL VSI (/vsizip/) 上で直接列挙・変換する（macOS の unzip は
# CP932 バイト列を APFS の UTF-8 パスとして書き出せず失敗するため）
idx=0
convert_errors=0
for zipfile in $vbm_zip_list; do
    zipname="$(basename "$zipfile")"
    echo "   処理対象: ${zipname}"

    shp_list="$(gdal vsi list -R -f json "/vsizip/${zipfile}" 2>&1 | jq -r '.[] | select(test("\\.shp$"; "i"))' || true)"
    if [ -z "$shp_list" ]; then
        echo "❌ [1. ZIP列挙] ${zipname} 内に .shp が見つかりません（gdal vsi list の失敗、またはアーカイブ構造が想定と異なる可能性）"
        exit 1
    fi

    while IFS= read -r shp_rel; do
        echo -n "     - ${shp_rel} ... "
        if err="$(ogr2ogr --config SHAPE_ENCODING CP932 -f GeoJSONSeq "$WORK_DIR/raw_${idx}.ndjson" \
            "/vsizip/${zipfile}/${shp_rel}" -skipfailures -nlt PROMOTE_TO_MULTI 2>&1)"; then
            n=$(wc -l < "$WORK_DIR/raw_${idx}.ndjson" | tr -d ' ')
            echo "${n} features"
        else
            echo "失敗"
            echo "❌ [1. ogr2ogr変換] ${zipname} 内 ${shp_rel} の変換に失敗しました:"
            echo "$err" | sed 's/^/       /'
            convert_errors=$((convert_errors + 1))
        fi
        idx=$((idx + 1))
    done <<< "$shp_list"
done

if [ "$convert_errors" -gt 0 ]; then
    echo "❌ [1. ogr2ogr変換] ${convert_errors} 件のシェープファイルで変換に失敗しました。上記のエラー内容を確認してください"
    exit 1
fi

echo ""
echo "2. GeoJSON Text Sequence を属性フィルタリング中..."

if ! cat "$WORK_DIR"/raw_*.ndjson > "$WORK_DIR/all_raw.ndjson" 2>&1; then
    echo "❌ [2. 結合] raw_*.ndjson の結合に失敗しました（work/vbm/ 配下の中間ファイルを確認してください）"
    exit 1
fi

if [ ! -s "$WORK_DIR/all_raw.ndjson" ]; then
    echo "❌ [2. 結合] all_raw.ndjson が空です（1. のいずれの shp からも feature が出力されていません）"
    exit 1
fi

total_features=$(wc -l < "$WORK_DIR/all_raw.ndjson" | tr -d ' ')
echo "   結合結果: ${total_features} features"

if ! jq -c '
    del(.properties["ID番号"]) |
    (.properties["分類コード"] // null) as $code |
    if $code == null then
        .
    else
        .tippecanoe = {
            "layer": ($code | tostring)
        }
        |
        if ($code == 7101 or $code == 7102 or $code == 7105 or $code == 7106 or $code == 7132 or $code == 7133 or $code == 7134 or $code == 7135) then
            .tippecanoe.minzoom = 13
        elif ($code == 2101 or $code == 2103 or $code == 2106 or $code == 2107) then
            .tippecanoe.minzoom = 13
        elif ($code == 3001 or $code == 3002 or $code == 3003 or $code == 3004) then
            .tippecanoe.minzoom = 13
        else
            .
        end
    end
' < "$WORK_DIR/all_raw.ndjson" > "$WORK_DIR/vbm_filtered.ndjson" 2>&1; then
    echo "❌ [2. jqフィルタリング] jq の実行に失敗しました（all_raw.ndjson の内容・エンコーディングを確認してください）"
    exit 1
fi

if [ ! -s "$WORK_DIR/vbm_filtered.ndjson" ]; then
    echo "❌ [2. jqフィルタリング] vbm_filtered.ndjson が空です"
    exit 1
fi

echo ""
echo "3. PMTiles を生成中..."

if ! tippecanoe --force -P -n "Hokkaido VBM" -A "測量法に基づく国土地理院長承認（使用）R 8JHs 207" -N "kitavolca-vbm" --no-progress-indicator -Z 5 -z 14 -o "${WORKSPACE_DIR}/dst/vbm.pmtiles" "$WORK_DIR/vbm_filtered.ndjson"; then
    echo "❌ [3. tippecanoe] PMTiles 生成に失敗しました（上記の tippecanoe 出力を確認してください）"
    exit 1
fi

echo ""
echo "✓ VBM PMTiles 生成完了: ${OUTPUT_FILE}"
