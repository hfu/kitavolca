#!/bin/bash
# build-vlcm.sh — VLCM の ZIP 内 Shapefile から PMTiles を生成
# ネイティブ実行（GDAL/tippecanoe が PATH にあること）を前提とする

set -euo pipefail

WORKSPACE_DIR="${1:-.}"
INPUT_DIR="${WORKSPACE_DIR}/src"
WORK_DIR="${WORKSPACE_DIR}/work/vlcm"
OUTPUT_FILE="${WORKSPACE_DIR}/dst/vlcm.pmtiles"

echo "=== VLCM PMTiles 生成 ==="
echo ""

for cmd in ogr2ogr gdal jq tippecanoe; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "❌ [事前チェック] '$cmd' が見つかりません。'just setup' で必要ツールを確認してください"; exit 1; }
done

mkdir -p "$WORK_DIR" "${WORKSPACE_DIR}/dst"
rm -f "$WORK_DIR"/*.geojson "$WORK_DIR"/*.ndjson 2>/dev/null || true

vlcm_zip_list="$(ls "$INPUT_DIR"/*_vlcm.zip 2>/dev/null || true)"
if [ -z "$vlcm_zip_list" ]; then
    echo "❌ [1. ZIP検出] VLCM の ZIP（*_vlcm.zip）が ${INPUT_DIR} に見つかりません"
    exit 1
fi

echo "1. ZIP から VLCM レイヤを抽出中..."

idx_n=0
idx_a=0
for zipfile in $vlcm_zip_list; do
    zipname="$(basename "$zipfile")"
    echo "   処理対象: ${zipname}"

    # ZIP 内パスの列挙は GDAL VSI 経由で行う（unzip の CP932/文字コード依存を避けるため）
    if ! gdal vsi list -R -f json "/vsizip/${zipfile}" > "$WORK_DIR/shp_list.json" 2>&1; then
        echo "❌ [1. ZIP列挙] ${zipname} の列挙に失敗しました（gdal vsi list エラー）:"
        cat "$WORK_DIR/shp_list.json" | sed 's/^/       /'
        exit 1
    fi
    jq -r '.[] | select(test("\\.shp$"; "i"))' "$WORK_DIR/shp_list.json" > "$WORK_DIR/shp_list.txt"
    if [ ! -s "$WORK_DIR/shp_list.txt" ]; then
        echo "   ⚠ ${zipname} に .shp が見つかりません"
        continue
    fi

    while IFS= read -r shp_rel; do
        shp_lower="$(printf '%s' "$shp_rel" | tr '[:upper:]' '[:lower:]')"

        if [[ "$shp_lower" == *shizen* ]]; then
            out="$WORK_DIR/natural_${idx_n}.ndjson"
            echo -n "     - natural: $shp_rel ... "
            if err="$(ogr2ogr -f GeoJSONSeq "$out" "/vsizip/${zipfile}/$shp_rel" -skipfailures -nlt PROMOTE_TO_MULTI 2>&1)"; then
                echo "$(wc -l < "$out" | tr -d ' ') features"
            else
                echo "失敗"
                echo "❌ [1. ogr2ogr変換] ${shp_rel} の変換に失敗しました:"
                echo "$err" | sed 's/^/       /'
                exit 1
            fi
            idx_n=$((idx_n + 1))
        elif [[ "$shp_lower" == *jinko* ]]; then
            out="$WORK_DIR/artificial_${idx_a}.ndjson"
            echo -n "     - artificial: $shp_rel ... "
            if err="$(ogr2ogr -f GeoJSONSeq "$out" "/vsizip/${zipfile}/$shp_rel" -skipfailures -nlt PROMOTE_TO_MULTI 2>&1)"; then
                echo "$(wc -l < "$out" | tr -d ' ') features"
            else
                echo "失敗"
                echo "❌ [1. ogr2ogr変換] ${shp_rel} の変換に失敗しました:"
                echo "$err" | sed 's/^/       /'
                exit 1
            fi
            idx_a=$((idx_a + 1))
        fi
    done < "$WORK_DIR/shp_list.txt"
done

if [ $idx_n -eq 0 ] && [ $idx_a -eq 0 ]; then
    echo "❌ [1. ZIP列挙] VLCM レイヤ抽出結果が 0 件です（ファイル名に shizen/jinko を想定）"
    exit 1
fi

if [ $idx_n -gt 0 ]; then
    cat "$WORK_DIR"/natural_*.ndjson > "$WORK_DIR/natural.ndjson"
fi
if [ $idx_a -gt 0 ]; then
    cat "$WORK_DIR"/artificial_*.ndjson > "$WORK_DIR/artificial.ndjson"
fi

echo ""
echo "2. 抽出結果から PMTiles を生成中..."

tippecanoe_args=(
    --force
    -P
    -n "Hokkaido VLCM"
    -A "火山土地条件図 測量法に基づく国土地理院長承認（使用）R 8JHs 207"
    -N "kitavolca-vlcm"
    --no-progress-indicator
    -Z 5
    -z 14
    -o "${WORKSPACE_DIR}/dst/vlcm.pmtiles"
)

if [ $idx_n -gt 0 ]; then
    tippecanoe_args+=( -L "natural:$WORK_DIR/natural.ndjson" )
fi
if [ $idx_a -gt 0 ]; then
    tippecanoe_args+=( -L "artificial:$WORK_DIR/artificial.ndjson" )
fi

if ! tippecanoe "${tippecanoe_args[@]}"; then
    echo "❌ [2. tippecanoe] PMTiles 生成に失敗しました（上記の tippecanoe 出力を確認してください）"
    exit 1
fi

echo ""
echo "✓ VLCM PMTiles 生成完了: ${OUTPUT_FILE}"
