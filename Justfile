# kitavolca — 北海道火山図パイプライン
# VBM + VLCM → PMTiles のタスク自動化

set shell := ["bash", "-c"]

# 既定タスク: 一覧表示
default:
    @just --list

# setup: Docker 環境の準備とツール確認
setup:
    #!/usr/bin/env bash
    set -e
    echo "=== kitavolca セットアップ ==="
    echo ""
    echo "1. Docker を確認中..."
    docker --version || (echo "❌ Docker が見つかりません" && exit 1)
    echo "   ✓ Docker 利用可能"
    echo ""
    
    echo "2. Docker イメージを構築中..."
    docker build -t kitavolca:latest . || (echo "❌ Docker ビルド失敗" && exit 1)
    echo "   ✓ イメージ構築完了"
    echo ""
    
    echo "3. src/ の入力データを確認中..."
    if [ -z "$(ls -A src/*.zip 2>/dev/null)" ]; then
        echo "   ⚠ src/ に ZIP が見つかりません（初回は正常です）"
        echo "   → VBM/VLCM ZIP をダウンロードして src/ に配置してください"
    else
        echo "   ✓ ZIP を $(ls -1 src/*.zip 2>/dev/null | wc -l) 件検出"
    fi
    echo ""
    
    echo "4. 出力ディレクトリを作成中..."
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
        
        docker run --rm -v "$(pwd)/src:/data:ro" kitavolca:latest \
            ogrinfo "/vsizip//data/$zipname" 2>&1 | grep -E "^[0-9]+:|Layer name:|Geometry|Feature Count" | head -20 || true
        
        echo ""
        echo "   属性サンプル（先頭レイヤ）:"
        docker run --rm -v "$(pwd)/src:/data:ro" kitavolca:latest \
            ogrinfo -al "/vsizip//data/$zipname" 2>&1 | grep -E "^  [A-Za-z0-9_]+ \(" | head -10 || true
        
        echo ""
    done
    
    echo "✓ 確認完了"
    echo ""
    echo "次: 構造を確認後、'just build-vlcm' または 'just build-vbm' を実行"

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

# validate: 生成 PMTiles の簡易確認
validate:
    #!/usr/bin/env bash
    set -e
    
    echo "=== PMTiles 出力確認 ==="
    echo ""
    
    errors=0
    
    for pmtiles in dst/vlcm.pmtiles dst/vbm.pmtiles; do
        if [ ! -f "$pmtiles" ]; then
            echo "⚠ 未生成: $pmtiles"
            continue
        fi
        
        echo "確認中: $pmtiles"
        size=$(du -h "$pmtiles" | cut -f1)
        echo "   サイズ: $size"
        
        # ogrinfo で確認（環境によって PMTiles ドライバが未有効な場合あり）
        docker run --rm -v "$(pwd)/dst:/data:ro" kitavolca:latest \
            ogrinfo "/data/$(basename "$pmtiles")" 2>&1 | head -30 || {
            echo "   ⚠ メタ情報の直接確認に失敗（ファイル生成自体は別途確認）"
        }
        echo ""
    done
    
    if [ $errors -eq 0 ]; then
        echo "✓ 確認完了"
    else
        echo "❌ 警告件数: $errors"
    fi

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
