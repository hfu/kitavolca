#!/bin/bash
# build-vbm.sh — VBM の ZIP 内 Shapefile から PMTiles を生成
# 分類コードベースでフィルタリングし、等高線系コードに minzoom=11 を適用

set -euo pipefail

WORKSPACE_DIR="${1:-.}"
INPUT_DIR="${WORKSPACE_DIR}/src"
WORK_DIR="${WORKSPACE_DIR}/work/vbm"
OUTPUT_FILE="${WORKSPACE_DIR}/dst/vbm.pmtiles"

echo "=== VBM PMTiles 生成（樽前山テスト）==="
echo ""

mkdir -p "$WORK_DIR" "${WORKSPACE_DIR}/dst"
rm -f "$WORK_DIR"/*.ndjson 2>/dev/null || true

if [ -f "$INPUT_DIR/tarumae_vbm.zip" ]; then
    vbm_zip_list="$INPUT_DIR/tarumae_vbm.zip"
else
    vbm_zip_list="$(ls "$INPUT_DIR"/*.zip 2>/dev/null | grep -Ei 'vbm|base' || true)"
fi
if [ -z "$vbm_zip_list" ]; then
    echo "❌ VBM の ZIP が ${INPUT_DIR} に見つかりません"
    exit 1
fi

echo "1. ZIP から VBM レイヤを抽出・変換中..."

for zipfile in $vbm_zip_list; do
    zipname="$(basename "$zipfile")"
    echo "   処理対象: ${zipname}"

    docker run --rm \
        -v "$INPUT_DIR:/data:ro" \
        -v "$WORK_DIR:/work" \
        kitavolca:latest \
        bash -lc '
            set -e
            rm -rf /tmp/vbm_extract
            mkdir -p /tmp/vbm_extract
            unzip -oq "/data/'"$zipname"'" -d /tmp/vbm_extract
            
            # すべての .shp ファイルを GeoJSON Text Sequence に変換
            idx=0
            while IFS= read -r -d "" shp; do
                echo "     - ${shp#/tmp/vbm_extract/}" >&2
                ogr2ogr --config SHAPE_ENCODING CP932 -f GeoJSONSeq "/work/raw_${idx}.ndjson" "$shp" -skipfailures -nlt PROMOTE_TO_MULTI 2>/dev/null || true
                idx=$((idx + 1))
            done < <(find /tmp/vbm_extract -type f -name "*.shp" -print0)
        '
done

echo ""
echo "2. GeoJSON Text Sequence を属性フィルタリング中..."

# すべての GeoJSON Text Sequence を結合して jq でフィルタリング
cat "$WORK_DIR"/raw_*.ndjson > "$WORK_DIR/all_raw.ndjson"

docker run --rm -i \
    -v "$WORK_DIR:/work" \
    kitavolca:latest \
    jq -c '
        del(.properties["ID番号"]) |
        (.properties["分類コード"] // null) as $code |
        if ($code == 7102 or $code == 7106 or $code == 7133 or $code == 7135) then
            .properties["tippecanoe.minzoom"] = 11
        else
            .
        end |
        if $code == null then
            .
        else
            .properties["tippecanoe.layer"] = ($code | tostring)
        end
    ' < "$WORK_DIR/all_raw.ndjson" > "$WORK_DIR/vbm_filtered.ndjson"

if [ ! -s "$WORK_DIR/vbm_filtered.ndjson" ]; then
    echo "❌ vbm_filtered.ndjson の生成に失敗しました"
    exit 1
fi


echo ""
echo "3. PMTiles を生成中..."

docker run --rm \
    -v "$WORK_DIR:/work:ro" \
    -v "${WORKSPACE_DIR}/dst:/output" \
    kitavolca:latest \
    bash -lc 'tippecanoe --force -P -n "Tarumaezan VBM" -A "GSI" -N "tarumaezan-vbm" --no-progress-indicator -Z 5 -z 14 -o /output/vbm.pmtiles /work/vbm_filtered.ndjson'

echo ""
echo "✓ VBM PMTiles 生成完了: ${OUTPUT_FILE}"
