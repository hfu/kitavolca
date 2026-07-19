const params = new URLSearchParams(location.search);
const useLocal = params.get('source') === 'local';
// `just serve` runs `pmtiles serve dst --port 8080 --public-url http://localhost:8080/`,
// which exposes a TileJSON at /<name>.json (same shape as Martin's production TileJSON,
// including the `attribution` baked in via tippecanoe -A).
const LOCAL_TILE_PORT = 8080;

fetch('style.json')
  .then(r => r.json())
  .then(style => {
    if (useLocal) {
      style.sources.vbm.url = `http://localhost:${LOCAL_TILE_PORT}/vbm.json`;
      style.sources.vlcm.url = `http://localhost:${LOCAL_TILE_PORT}/vlcm.json`;
    }

    // Group style layer ids by source, so a single checkbox can toggle every
    // layer that belongs to one of the 4 switchable groups (bvmap/vbm/vlcm/
    // seamlessphoto). Layers with no `source` (e.g. `background`) or whose
    // source isn't one of those 4 (e.g. `mapterhorn`, used only for
    // terrain/hillshade) are naturally excluded and left untouched.
    const layerIdsBySource = new Map();
    for (const layer of style.layers) {
      if (!layer.source) continue;
      const list = layerIdsBySource.get(layer.source) ?? [];
      list.push(layer.id);
      layerIdsBySource.set(layer.source, list);
    }

    // VLCM color legend: `vlcm-natural-fill`'s fill-color is a flat
    // ["match", ["get","name"], label1, color1, ..., labelN, colorN, <fallback>]
    // expression. The trailing fallback isn't a color string (it's a nested
    // code2-based match expression), so it's excluded by slice(2, -1).
    function parseVlcmLegend() {
      const layer = style.layers.find(l => l.id === 'vlcm-natural-fill');
      const expr = layer?.paint?.['fill-color'];
      const map = new Map();
      if (!Array.isArray(expr) || expr[0] !== 'match') return map;
      const pairs = expr.slice(2, -1);
      for (let i = 0; i < pairs.length; i += 2) {
        map.set(pairs[i], pairs[i + 1]);
      }
      return map;
    }
    const vlcmNameColor = parseVlcmLegend();

    const map = new maplibregl.Map({
      container: 'map',
      style,
      hash: 'hash',
      center: [141.38, 42.69], // 樽前山
      zoom: 11,
      pitch: 50,
      // bvmap のラベルは NotoSansJP/NotoSerifJP のグリフを参照するが、
      // CJK文字はブラウザのシステム sans-serif フォントで描画させる
      // （何千もの漢字グリフPBFを取得せずに済み、表示も速い）
      localIdeographFontFamily: 'sans-serif'
    });
    map.addControl(new maplibregl.NavigationControl(), 'top-right');
    map.addControl(new maplibregl.ScaleControl(), 'bottom-left');
    map.addControl(new maplibregl.TerrainControl({ source: 'mapterhorn', exaggeration: 1 }), 'top-right');

    // Attribute filtering for the feature popup: VBM's and VLCM's raw
    // properties mix human-readable text (名称/注記, VLCM's class1-6/name)
    // with numeric/coded metadata (ID番号, 分類コード, 標高, 水深, three-角点
    // 標高 etc.) that's meaningless without a code table. Default to only the
    // former; the "詳細" checkbox reveals everything (unfiltered, as before).
    const VBM_PUBLIC_KEYS = new Set(['名称', '注記']);
    const VLCM_PUBLIC_KEYS = new Set(['name', 'class1', 'class2', 'class3', 'class4', 'class5', 'class6']);
    const isVlcmSourceLayer = (sourceLayer) => sourceLayer === 'natural' || sourceLayer === 'artificial';

    function publicFriendlyEntries(properties, sourceLayer) {
      const allowed = isVlcmSourceLayer(sourceLayer) ? VLCM_PUBLIC_KEYS : VBM_PUBLIC_KEYS;
      return Object.entries(properties).filter(([k, v]) => allowed.has(k) && v != null && v !== '');
    }

    function popupHTML(features, showAll) {
      const rows = features.map((f) => {
        const sourceLayer = f.layer['source-layer'] || f.layer.id;
        const entries = showAll ? Object.entries(f.properties) : publicFriendlyEntries(f.properties, sourceLayer);
        const attrText = entries.length
          ? entries.map(([k, v]) => `${k}=${v}`).join(', ')
          : '<span class="attr-empty">（表示できる属性なし）</span>';
        return `<tr><td><code>${sourceLayer}</code></td><td>${attrText}</td></tr>`;
      }).join('');
      return `<div class="feature-popup">
        <label class="dads-checkbox" data-size="sm">
          <span class="dads-checkbox__checkbox"><input class="dads-checkbox__input" type="checkbox" id="popup-details-toggle"${showAll ? ' checked' : ''}></span>
          <span class="dads-checkbox__label">詳細</span>
        </label>
        <table>${rows}</table>
      </div>`;
    }

    // Remembers the "詳細" state across clicks (module-level, not per-popup),
    // so once a user opts into full attributes they stay expanded on the next click.
    let showAllAttributes = false;

    map.on('click', (e) => {
      const features = map.queryRenderedFeatures(e.point).slice(0, 8);
      if (!features.length) return;
      // addTo(map) must run before the first render(): popup.getElement()
      // returns undefined until the popup's DOM is actually mounted, which
      // would silently skip attaching the checkbox's change listener.
      const popup = new maplibregl.Popup().setLngLat(e.lngLat).addTo(map);
      const render = () => {
        popup.setHTML(popupHTML(features, showAllAttributes));
        const toggle = popup.getElement()?.querySelector('#popup-details-toggle');
        toggle?.addEventListener('change', () => {
          showAllAttributes = toggle.checked;
          render();
        });
      };
      render();
    });

    // Layer group checkboxes: only flips `visibility`, never reorders
    // `style.layers`, so draw order is always preserved.
    document.querySelectorAll('[data-layer-toggle]').forEach((el) => {
      el.addEventListener('change', () => {
        const id = el.getAttribute('data-layer-toggle');
        for (const layerId of layerIdsBySource.get(id) ?? []) {
          map.setLayoutProperty(layerId, 'visibility', el.checked ? 'visible' : 'none');
        }
        if (id === 'vlcm') updateLegend();
      });
    });

    // Recomputed on `idle` (not `moveend`): moveend fires before newly
    // panned-into tiles finish loading, which would undercount the names
    // actually visible right after a pan.
    function updateLegend() {
      const el = document.querySelector('.vlcm-legend');
      const vlcmCheckbox = document.querySelector('[data-layer-toggle="vlcm"]');
      if (!el || !vlcmCheckbox) return;
      if (!vlcmCheckbox.checked || !map.getLayer('vlcm-natural-fill')) {
        el.innerHTML = '';
        return;
      }
      const names = new Set(
        map.queryRenderedFeatures({ layers: ['vlcm-natural-fill'] })
          .map(f => f.properties.name)
          .filter(Boolean)
      );
      if (names.size === 0) {
        el.innerHTML = '<p class="legend-empty">（表示範囲に凡例なし）</p>';
        return;
      }
      el.innerHTML = [...names].sort().map((name) => {
        const color = vlcmNameColor.get(name) ?? '#ccc';
        return `<div class="legend-row"><span class="legend-swatch" style="background:${color}"></span><span>${name}</span></div>`;
      }).join('');
    }
    map.on('idle', updateLegend);

    // Seamless photo opacity: an independent "不透過" checkbox layered on top of
    // the existing visibility checkbox. The original raster-opacity expression
    // (zoom-dependent, tuned so the photo doesn't overpower thematic layers) is
    // captured once from the style before any mutation, so unchecking always
    // restores the exact original expression rather than a hand-reconstructed one.
    const originalSeamlessOpacity = style.layers.find(l => l.id === 'seamlessphoto')?.paint?.['raster-opacity'];
    const opaqueToggle = document.getElementById('seamlessphoto-opaque');
    opaqueToggle.addEventListener('change', () => {
      map.setPaintProperty('seamlessphoto', 'raster-opacity', opaqueToggle.checked ? 1 : originalSeamlessOpacity);
    });

    // Terrain checkbox: independent from the layer-visibility checkboxes above
    // (mapterhorn's hillshade layer toggles via data-layer-toggle, but terrain
    // is map.setTerrain(), not a style layer). Listen for the 'terrain' event
    // so the checkbox also follows the existing top-right TerrainControl
    // button -- whichever control the user clicks, both stay in sync.
    const terrainToggle = document.getElementById('terrain-toggle');
    terrainToggle.addEventListener('change', () => {
      map.setTerrain(terrainToggle.checked ? { source: 'mapterhorn', exaggeration: 1 } : null);
    });
    map.on('terrain', () => {
      terrainToggle.checked = !!map.getTerrain();
    });

    // Panel collapse toggle
    const panelEl = document.querySelector('.panel');
    const panelToggle = document.getElementById('panel-toggle');
    panelToggle.addEventListener('click', () => {
      const collapsed = panelEl.dataset.collapsed === 'true';
      panelEl.dataset.collapsed = collapsed ? 'false' : 'true';
      panelToggle.setAttribute('aria-expanded', collapsed ? 'true' : 'false');
    });
  })
  .catch(err => {
    const content = document.querySelector('.panel__content');
    if (content) {
      content.innerHTML += `<div class="notice error">style.json の読み込みに失敗: ${err}</div>`;
    }
  });
