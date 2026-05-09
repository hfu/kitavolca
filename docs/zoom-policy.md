# Zoom Policy (TBD)

**This document is to be completed after the first successful pipeline run with real input data.**

## Purpose

Define zoom level allocation for tiles, including:
- Minimum zoom level (where tiling starts)
- Maximum zoom level (maximum detail/resolution)
- Feature simplification/generalization strategies per zoom range
- Inclusion/exclusion rules (e.g., which features appear at which zoom levels)

## VBM Zoom Policy (To be determined)

**Status**: TBD — Pending inspection of actual VBM Shapefile extent and geometry complexity

### Planned Approach

1. **Initial Build**: `tippecanoe` currently configured with `-z 0 -Z 14` (zoom 0–14)
2. **Assessment**: After first build, evaluate:
   - Tile size distribution (are tiles too large at low zoom? Too small at high zoom?)
   - Performance impact (does navigation feel responsive?)
   - Geometry complexity (do small features become invisible at low zoom? Do they render correctly at high zoom?)
3. **Refinement**: Adjust zoom levels and feature filtering rules based on observations

## VLCM Zoom Policy (To be determined)

**Status**: TBD — Pending inspection of actual VLCM Shapefile extent and geometry complexity

### Planned Approach

Same as VBM (see above).

## Configuration

The zoom policy is controlled in:
- `scripts/build-vlcm.sh` — line with `tippecanoe ... -z 0 -Z 14`
- `scripts/build-vbm.sh` — line with `tippecanoe ... -z 0 -Z 14`

Example adjustment:
```bash
# Current (default)
tippecanoe -z 0 -Z 14 ...

# If tiles are too large at low zoom:
tippecanoe -z 2 -Z 15 ...

# If simplification is needed (reduce detail at low zoom):
tippecanoe -z 0 -Z 14 -r 2 ...  # -r sets tile resolution
```

## Simplification Strategy

tippecanoe supports multiple options for controlling feature detail:

- **`-r<n>`**: Tile resolution (default 4; higher = more detail)
- **`-C<n>`**: Tile cluster radius (default 50; prevents point clustering issues)
- **Feature filtering**: Use `-w` to drop small features at low zoom

### Decision Tree

1. **Is tile size at zoom 0–2 too large?** → Reduce `-Z` or increase `-r`
2. **Is there too much detail at low zoom?** → Increase simplification or use layer-specific zoom ranges
3. **Are features disappearing unexpectedly?** → Reduce `-r` or lower `-z`

## References

- [tippecanoe zoom parameter documentation](https://github.com/felt/tippecanoe)
- [PMTiles specification (zoom encoding)](https://github.com/protomaps/PMTiles)
- Web Mercator projection and typical zoom levels: https://wiki.openstreetmap.org/wiki/Zoom_levels
