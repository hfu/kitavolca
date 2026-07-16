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

    map.on('click', (e) => {
      const features = map.queryRenderedFeatures(e.point);
      if (!features.length) return;
      const rows = features.slice(0, 8).map(f =>
        `<tr><td><code>${f.layer['source-layer'] || f.layer.id}</code></td><td>${
          Object.entries(f.properties).map(([k, v]) => `${k}=${v}`).join(', ')
        }</td></tr>`
      ).join('');
      new maplibregl.Popup()
        .setLngLat(e.lngLat)
        .setHTML(`<table style="font-size:12px">${rows}</table>`)
        .addTo(map);
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
      content.innerHTML += `<div style="color:#b00">style.json の読み込みに失敗: ${err}</div>`;
    }
  });
