#!/bin/bash
# build-vlcm.sh — VLCM の ZIP 内 Shapefile から PMTiles を生成

set -euo pipefail

WORKSPACE_DIR="${1:-.}"
INPUT_DIR="${WORKSPACE_DIR}/src"
WORK_DIR="${WORKSPACE_DIR}/work/vlcm"
OUTPUT_FILE="${WORKSPACE_DIR}/dst/vlcm.pmtiles"

echo "=== VLCM PMTiles 生成（樽前山テスト）==="
echo ""

mkdir -p "$WORK_DIR" "${WORKSPACE_DIR}/dst"
rm -f "$WORK_DIR"/*.geojson "$WORK_DIR"/*.ndjson 2>/dev/null || true

if [ -f "$INPUT_DIR/tarumae_vlcm.zip" ]; then
    vlcm_zip_list="$INPUT_DIR/tarumae_vlcm.zip"
else
    vlcm_zip_list="$(ls "$INPUT_DIR"/*.zip 2>/dev/null | grep -Ei 'vlcm|land|condition' || true)"
fi
if [ -z "$vlcm_zip_list" ]; then
    echo "❌ VLCM の ZIP が ${INPUT_DIR} に見つかりません"
    exit 1
fi

echo "1. ZIP から VLCM レイヤを抽出中..."

idx_n=0
idx_a=0
for zipfile in $vlcm_zip_list; do
    zipname="$(basename "$zipfile")"
    echo "   処理対象: ${zipname}"

    (cd "$INPUT_DIR" && unzip -Z1 "$zipname" | LC_ALL=C grep -Ei '\.shp$' || true) > "$WORK_DIR/shp_list.txt"
    if [ ! -s "$WORK_DIR/shp_list.txt" ]; then
        echo "   ⚠ ${zipname} に .shp が見つかりません"
        continue
    fi

    while IFS= read -r shp_rel; do
        shp_lower="$(printf '%s' "$shp_rel" | tr '[:upper:]' '[:lower:]')"

        if [[ "$shp_lower" == *shizen* ]]; then
            out="/work/natural_${idx_n}.ndjson"
            echo "     - natural: $shp_rel"
            docker run --rm \
                -v "$INPUT_DIR:/data:ro" \
                -v "$WORK_DIR:/work" \
                kitavolca:latest \
                ogr2ogr -f GeoJSONSeq "$out" "/vsizip//data/$zipname/$shp_rel" -skipfailures -nlt PROMOTE_TO_MULTI >/dev/null
            idx_n=$((idx_n + 1))
        elif [[ "$shp_lower" == *jinko* ]]; then
            out="/work/artificial_${idx_a}.ndjson"
            echo "     - artificial: $shp_rel"
            docker run --rm \
                -v "$INPUT_DIR:/data:ro" \
                -v "$WORK_DIR:/work" \
                kitavolca:latest \
                ogr2ogr -f GeoJSONSeq "$out" "/vsizip//data/$zipname/$shp_rel" -skipfailures -nlt PROMOTE_TO_MULTI >/dev/null
            idx_a=$((idx_a + 1))
        fi
    done < "$WORK_DIR/shp_list.txt"
done

if [ $idx_n -eq 0 ] && [ $idx_a -eq 0 ]; then
    echo "❌ VLCM レイヤ抽出結果が 0 件です（shizen/jinko を想定）"
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
    -n "Tarumaezan VLCM"
    -A "GSI"
    -N "tarumaezan-vlcm"
    --no-progress-indicator
    -Z 5
    -z 14
    -o /output/vlcm.pmtiles
)

if [ $idx_n -gt 0 ]; then
    tippecanoe_args+=( -L "natural:/work/natural.ndjson" )
fi
if [ $idx_a -gt 0 ]; then
    tippecanoe_args+=( -L "artificial:/work/artificial.ndjson" )
fi

docker run --rm \
    -v "$WORK_DIR:/work:ro" \
    -v "${WORKSPACE_DIR}/dst:/output" \
    kitavolca:latest \
    tippecanoe "${tippecanoe_args[@]}"

echo ""
echo "✓ VLCM PMTiles 生成完了: ${OUTPUT_FILE}"
