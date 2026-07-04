#!/bin/bash
# fetch-vlcm.sh — GSI の VLCM 一覧ページから指定火山の Shapefile ZIP を取得し src/ に配置する
#
# 一覧ページ (bousaichiri41114.html) は VBM 一覧ページと異なり、火山ごとの
# <a id="..."> アンカーを持たない（地域見出し id="hokkaido"/"tohoku"/... はあるが
# 個々の火山を指す id は無い）。その代わり、ダウンロードリンクのファイル名に
# 「2桁の火山コード + ローマ字3文字」（例: 05trm = 樽前山）が埋め込まれており、
# この数字コードは VBM 側（vbmNN）と共通である。そのため volcano_id → vlcm コード
# の対応表をここに持ち、コードでリンクを直接検索する方式にしている。
#
# 対応表は 2026-07-04 時点でページを実測して確認したものだけを記載している。
# 未掲載の火山は、まずページで実際に vlcm_shp-<コード>.zip が存在するか確認し、
# 判明したら下記マップに追加すること。

set -euo pipefail

# macOS 標準の /bin/bash は 3.2 系で連想配列(declare -A)が使えないため、
# volcano_id -> vlcm コードの対応表は case 文で持つ（KNOWN_VOLCANOES は
# エラーメッセージ表示用の一覧）
KNOWN_VOLCANOES="meakan tokachi tarumae usu hokaikoma esan"
vlcm_code_for() {
    case "$1" in
        meakan) echo "02mak" ;;
        tokachi) echo "04tkc" ;;
        tarumae) echo "05trm" ;;
        usu) echo "07usu" ;;
        hokaikoma) echo "08hkm" ;;
        esan) echo "09esn" ;;
        *) echo "" ;;
    esac
}

VOLCANO_ID="${1:-}"
WORKSPACE_DIR="${2:-.}"
SRC_DIR="${WORKSPACE_DIR}/src"
LIST_URL="https://www.gsi.go.jp/bousaichiri/bousaichiri41114.html"

if [ -z "$VOLCANO_ID" ]; then
    echo "使い方: fetch-vlcm.sh <volcano_id> [workspace_dir]"
    echo "  例:   fetch-vlcm.sh tarumae"
    echo "  対応済み volcano_id: ${KNOWN_VOLCANOES}"
    exit 1
fi

CODE="$(vlcm_code_for "$VOLCANO_ID")"
if [ -z "$CODE" ]; then
    echo "❌ [事前チェック] volcano_id '${VOLCANO_ID}' は対応表(vlcm_code_for)にありません"
    echo "   対応済み: ${KNOWN_VOLCANOES}"
    echo "   ${LIST_URL} を確認し、Shapefile が存在すればスクリプト内の対応表に追加してください"
    exit 1
fi

OUT_FILE="${SRC_DIR}/${VOLCANO_ID}_vlcm.zip"
LIST_CACHE="$(mktemp -t kitavolca-vlcm-list)"
trap 'rm -f "$LIST_CACHE"' EXIT

echo "=== VLCM ZIP 取得: ${VOLCANO_ID} (code=${CODE}) ==="
echo ""
mkdir -p "$SRC_DIR"

echo "1. 一覧ページを取得中... (${LIST_URL})"
if ! curl -sL --fail --max-time 30 -o "$LIST_CACHE" "$LIST_URL"; then
    echo "❌ [1. 一覧取得] ページの取得に失敗しました: ${LIST_URL}"
    exit 1
fi
if [ ! -s "$LIST_CACHE" ]; then
    echo "❌ [1. 一覧取得] ページが空です: ${LIST_URL}"
    exit 1
fi

echo "2. コード '${CODE}' の Shapefile ダウンロードリンクを検索中..."

zip_url="$(command grep -oE "href=\"[^\"]+vlcm_shp-${CODE}[^\"]*\.zip\"" "$LIST_CACHE" | head -1 | sed -E 's/^href="//; s/"$//')"

if [ -z "$zip_url" ]; then
    echo "❌ [2. リンク検索] コード '${CODE}' の Shapefile (vlcm_shp-${CODE}*.zip) リンクが見つかりません"
    echo "   ${LIST_URL} でページ構成が変わっていないか確認してください"
    exit 1
fi

echo "   見つかりました: ${zip_url}"
echo ""
echo "3. ダウンロード中..."

if ! curl -sL --fail --max-time 300 -o "$OUT_FILE" "$zip_url"; then
    echo "❌ [3. ダウンロード] ${zip_url} の取得に失敗しました"
    rm -f "$OUT_FILE"
    exit 1
fi

size=$(du -h "$OUT_FILE" | cut -f1)
echo ""
echo "✓ 取得完了: ${OUT_FILE} (${size})"
