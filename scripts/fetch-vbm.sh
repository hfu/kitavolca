#!/bin/bash
# fetch-vbm.sh — GSI の VBM データ一覧ページから指定火山の Shapefile ZIP を取得し src/ に配置する
#
# 一覧ページ (vbm-data_hokkai_tohoku.html) は各火山ごとに
#   <a ... id="<volcano_id>" ...>火山名：...</a>
# というアンカーを持ち、直後の table 内に "*-shp.zip" へのリンクがある。
# この構造を前提に、id から対応する Shapefile ZIP の URL を抽出してダウンロードする。
#
# 一覧ページ(数百KB)は一時ファイルに保存してから grep/awk にファイル引数で渡す
# （シェル変数に保持したままパイプで渡すと、環境によっては正しく読み取れない
#   ことがあるため。ファイル引数渡しの方が確実）。

set -euo pipefail

VOLCANO_ID="${1:-}"
WORKSPACE_DIR="${2:-.}"
SRC_DIR="${WORKSPACE_DIR}/src"
LIST_URL="https://web1.gsi.go.jp/bousaichiri/vbm-data_hokkai_tohoku.html"

if [ -z "$VOLCANO_ID" ]; then
    echo "使い方: fetch-vbm.sh <volcano_id> [workspace_dir]"
    echo "  例:   fetch-vbm.sh tarumae"
    echo "  volcano_id は ${LIST_URL} 内の <a id=\"...\"> 属性値（例: tarumae, meakan, usu）"
    exit 1
fi

OUT_FILE="${SRC_DIR}/${VOLCANO_ID}_vbm.zip"
LIST_CACHE="$(mktemp -t kitavolca-vbm-list)"
trap 'rm -f "$LIST_CACHE"' EXIT

echo "=== VBM ZIP 取得: ${VOLCANO_ID} ==="
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

if ! command grep -qF "id=\"${VOLCANO_ID}\"" "$LIST_CACHE"; then
    echo "❌ [1. 一覧取得] volcano_id '${VOLCANO_ID}' が一覧ページに見つかりません"
    echo "   ${LIST_URL} を開いて <a id=\"...\"> の値を確認してください"
    exit 1
fi

echo "2. '${VOLCANO_ID}' の Shapefile ダウンロードリンクを検索中..."

# id="<volcano_id>" のアンカーから、次の id="..." アンカー（＝次の火山）が
# 現れるまでの範囲に絞り、その中の最初の *-shp.zip リンクを採用する
zip_url="$(command awk -v vid="$VOLCANO_ID" '
    BEGIN { found = 0 }
    {
        if ($0 ~ ("id=\"" vid "\"")) { found = 1 }
        else if (found && match($0, /id="[a-zA-Z0-9_-]+"/)) { exit }
        if (found) print
    }
' "$LIST_CACHE" | command grep -oE 'href="[^"]+-shp\.zip"' | head -1 | sed -E 's/^href="//; s/"$//')"

if [ -z "$zip_url" ]; then
    echo "❌ [2. リンク検索] '${VOLCANO_ID}' の Shapefile (*-shp.zip) リンクが見つかりません"
    echo "   その火山はまだ Shapefile 形式で提供されていない可能性があります: ${LIST_URL}"
    exit 1
fi

echo "   見つかりました: ${zip_url}"
echo ""
echo "3. ダウンロード中..."

if ! curl -sL --fail --max-time 600 -o "$OUT_FILE" "$zip_url"; then
    echo "❌ [3. ダウンロード] ${zip_url} の取得に失敗しました"
    rm -f "$OUT_FILE"
    exit 1
fi

size=$(du -h "$OUT_FILE" | cut -f1)
echo ""
echo "✓ 取得完了: ${OUT_FILE} (${size})"
