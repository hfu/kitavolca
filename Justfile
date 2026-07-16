# kitavolca — 北海道火山図パイプライン
# VBM + VLCM → PMTiles のタスク自動化

set shell := ["bash", "-c"]

# 既定タスク: 一覧表示
default:
    @just --list

# setup: ネイティブツールの確認
setup:
    #!/usr/bin/env bash
    set -e
    echo "=== kitavolca セットアップ ==="
    echo ""
    echo "1. 必須ツールを確認中..."
    missing=0
    for cmd in ogr2ogr ogrinfo gdal tippecanoe jq; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "   ✓ $cmd ($($cmd --version 2>&1 | head -1))"
        else
            echo "   ❌ $cmd が見つかりません"
            missing=1
        fi
    done
    if [ "$missing" -eq 1 ]; then
        echo ""
        echo "不足しているツールをインストールしてください（macOS/Homebrew の例）:"
        echo "  brew install gdal tippecanoe jq"
        exit 1
    fi
    echo ""

    echo "2. src/ の入力データを確認中..."
    if [ -z "$(ls -A src/*.zip 2>/dev/null)" ]; then
        echo "   ⚠ src/ に ZIP が見つかりません（初回は正常です）"
        echo "   → VBM/VLCM ZIP をダウンロードして src/ に配置してください"
    else
        echo "   ✓ ZIP を $(ls -1 src/*.zip 2>/dev/null | wc -l) 件検出"
    fi
    echo ""
    
    echo "3. 出力ディレクトリを作成中..."
    mkdir -p dst/
    echo "   ✓ dst/ 準備完了"
    echo ""
    
    echo "=== セットアップ完了 ==="
    echo "次: 'just inspect' で入力データを確認"

# inspect: ZIP を展開せずに内容確認
inspect:
    #!/usr/bin/env bash
    set -e
    
    if [ -z "$(ls -A src/*.zip 2>/dev/null)" ]; then
        echo "❌ src/ に ZIP ファイルがありません"
        echo ""
        echo "パイプラインを試すには、以下からデータを取得してください:"
        echo ""
        echo "VBM（火山基本図）:"
        echo "  https://web1.gsi.go.jp/bousaichiri/vbm-data_hokkai_tohoku.html"
        echo ""
        echo "VLCM（火山土地条件図）:"
        echo "  https://web2.gsi.go.jp/bousaichiri/volcano-maps-vlcm-data.html"
        echo ""
        echo "ZIP を src/ に配置してから再実行してください。"
        exit 1
    fi
    
    echo "=== 入力データ確認 ==="
    echo ""
    
    for zipfile in src/*.zip; do
        zipname=$(basename "$zipfile")
        echo "📦 ファイル: $zipname"
        echo "   サイズ: $(du -h "$zipfile" | cut -f1)"
        echo ""
        echo "   アーカイブ内レイヤ:"
        
        ogrinfo "/vsizip/$(pwd)/src/$zipname" 2>&1 | grep -E "^[0-9]+:|Layer name:|Geometry|Feature Count" | head -20 || true

        echo ""
        echo "   属性サンプル（先頭レイヤ）:"
        ogrinfo -al "/vsizip/$(pwd)/src/$zipname" 2>&1 | grep -E "^  [A-Za-z0-9_]+ \(" | head -10 || true
        
        echo ""
    done
    
    echo "✓ 確認完了"
    echo ""
    echo "次: 構造を確認後、'just build-vlcm' または 'just build-vbm' を実行"

# fetch-vbm: GSI の一覧ページから指定火山の VBM Shapefile ZIP を取得し src/ へ配置（volcano_id は README 参照）
fetch-vbm volcano_id:
    #!/usr/bin/env bash
    set -e
    bash scripts/fetch-vbm.sh "{{volcano_id}}" "$(pwd)"

# fetch-vlcm: GSI の一覧ページから指定火山の VLCM Shapefile ZIP を取得し src/ へ配置（volcano_id は README 参照）
fetch-vlcm volcano_id:
    #!/usr/bin/env bash
    set -e
    bash scripts/fetch-vlcm.sh "{{volcano_id}}" "$(pwd)"

# build-vlcm: VLCM から PMTiles を生成
build-vlcm:
    #!/usr/bin/env bash
    set -e
    bash scripts/build-vlcm.sh "$(pwd)"

# build-vbm: VBM から PMTiles を生成
build-vbm:
    #!/usr/bin/env bash
    set -e
    bash scripts/build-vbm.sh "$(pwd)"

# validate: 出力 PMTiles と中間データの機械検証
validate:
    #!/usr/bin/env bash
    set -e

    errors=0

    echo "=== 1. 出力ファイルの存在・可読性確認 ==="
    for pmtiles in dst/vlcm.pmtiles dst/vbm.pmtiles; do
        if [ ! -f "$pmtiles" ]; then
            echo "❌ 未生成: $pmtiles"
            errors=$((errors + 1))
            continue
        fi
        size=$(du -h "$pmtiles" | cut -f1)
        if ogrinfo "$pmtiles" >/dev/null 2>&1; then
            echo "✓ $pmtiles ($size, PMTiles として読み取り可能)"
        else
            echo "❌ $pmtiles ($size) — GDAL PMTiles ドライバで開けません"
            errors=$((errors + 1))
        fi
    done
    echo ""

    echo "=== 2. VBM 中間データ検証（work/vbm/vbm_filtered.ndjson）==="
    vbm_ndjson="work/vbm/vbm_filtered.ndjson"
    if [ -f "$vbm_ndjson" ]; then
        n=$(jq -c 'select(.properties["ID番号"] != null)' "$vbm_ndjson" | wc -l | tr -d ' ')
        [ "$n" = "0" ] && echo "✓ ID番号は削除済み" || { echo "❌ ID番号が残存: ${n}件"; errors=$((errors + 1)); }

        n=$(jq -c 'select(.properties["分類コード"] != null and .tippecanoe.layer == null)' "$vbm_ndjson" | wc -l | tr -d ' ')
        [ "$n" = "0" ] && echo "✓ 分類コードを持つ全 feature に tippecanoe.layer あり" || { echo "❌ tippecanoe.layer 欠落: ${n}件"; errors=$((errors + 1)); }

        n=$(jq -c '.tippecanoe.layer as $l | select(["7101","7102","7105","7106","7132","7133","7134","7135","2101","2103","2106","2107","3001","3002","3003","3004"] | index($l)) | select(.tippecanoe.minzoom != 13)' "$vbm_ndjson" | wc -l | tr -d ' ')
        [ "$n" = "0" ] && echo "✓ 等高線・道路・建物系コードは全て minzoom=13" || { echo "❌ 等高線・道路・建物系コードに minzoom=13 が付与されていない feature: ${n}件"; errors=$((errors + 1)); }

        known="出典コード 出典レベル 分類コード 標高 水深 水深値 名称 注記 表示区分 三角点標高 水準点標高"
        unexpected=$(jq -r '.properties | keys[]' "$vbm_ndjson" | sort -u | while read -r k; do
            printf '%s\n' "$known" | tr ' ' '\n' | grep -qxF "$k" || echo "$k"
        done)
        if [ -z "$unexpected" ]; then
            echo "✓ 想定外の属性キーなし"
        else
            echo "❌ 想定外の属性キー: $(echo "$unexpected" | tr '\n' ' ')"
            errors=$((errors + 1))
        fi
    else
        echo "⚠ ${vbm_ndjson} が見つかりません（'just build-vbm' 未実行、または work/ が削除済み）。中間データ検証をスキップ"
    fi
    echo ""

    echo "=== 3. VLCM 中間データ検証（work/vlcm/*.ndjson）==="
    vlcm_found=0
    for f in work/vlcm/natural.ndjson work/vlcm/artificial.ndjson; do
        [ -f "$f" ] || continue
        vlcm_found=1
        known="ID code1 code2 code3 code4 code5 code6 code class1 class2 class3 class4 class5 class6 name"
        unexpected=$(jq -r '.properties | keys[]' "$f" | sort -u | while read -r k; do
            printf '%s\n' "$known" | tr ' ' '\n' | grep -qxF "$k" || echo "$k"
        done)
        if [ -z "$unexpected" ]; then
            echo "✓ $f: 属性キーは想定通り"
        else
            echo "❌ $f: 想定外の属性キー: $(echo "$unexpected" | tr '\n' ' ')"
            errors=$((errors + 1))
        fi
    done
    [ "$vlcm_found" = "0" ] && echo "⚠ work/vlcm/*.ndjson が見つかりません（'just build-vlcm' 未実行、または work/ が削除済み）。中間データ検証をスキップ"
    echo ""

    if [ "$errors" -eq 0 ]; then
        echo "✓ すべての検証に合格"
    else
        echo "❌ 検証エラー: ${errors}件"
        exit 1
    fi

# upload: 生成済み PMTiles を本番サーバー (stars.optgeo.org) へ rsync でアップロード
upload:
    #!/usr/bin/env bash
    set -e
    for pmtiles in dst/vbm.pmtiles dst/vlcm.pmtiles; do
        [ -f "$pmtiles" ] || { echo "❌ $pmtiles が見つかりません。先に 'just build-vbm'/'just build-vlcm' を実行してください"; exit 1; }
    done
    echo "=== 本番サーバーへアップロード ==="
    for pmtiles in dst/vbm.pmtiles dst/vlcm.pmtiles; do
        echo "→ $pmtiles"
        rsync --progress "$pmtiles" stars@stars.local:/home/stars/data/
    done
    echo "✓ アップロード完了"

# clean: 生成物の削除
clean:
    #!/usr/bin/env bash
    set -e
    
    echo "=== 生成物クリーンアップ ==="
    
    if [ -d dst ]; then
        echo "dst/ を削除中..."
        rm -rf dst/
        echo "✓ dst/ を削除"
    fi
    
    if [ -d work ]; then
        echo "work/（中間ファイル）を削除中..."
        rm -rf work/
        echo "✓ work/ を削除"
    fi
    
    # そのほか中間ファイル
    rm -f *.geojson *.ndjson 2>/dev/null || true

    echo "✓ クリーンアップ完了"

# serve: docs/ のプレビューサイトとローカル dst/*.pmtiles を配信（ローカル動作確認用）
serve:
    #!/usr/bin/env bash
    set -e
    for pmtiles in dst/vbm.pmtiles dst/vlcm.pmtiles; do
        [ -f "$pmtiles" ] || { echo "❌ $pmtiles が見つかりません。先に 'just build-vbm'/'just build-vlcm' を実行してください"; exit 1; }
    done
    echo "=== ローカルプレビュー起動 ==="
    echo "  サイト:   http://localhost:8000/?source=local"
    echo "  タイル:   http://localhost:8080/ (pmtiles serve, Ctrl+C で両方停止)"
    echo ""
    pmtiles serve dst --port 8080 --cors "*" --public-url http://localhost:8080/ &
    TILE_PID=$!
    trap 'kill "$TILE_PID" 2>/dev/null' EXIT
    (cd docs && python3 -m http.server 8000)
