# Schema Definition (TBD)

**This document is to be completed after the first successful pipeline run with real input data.**

## Purpose

Define which attributes (fields) to preserve from the raw Shapefile data during the conversion to PMTiles. This determines what information is available for styling and querying in MapLibre.

## VBM Schema (To be determined)

**Status**: TBD — Pending inspection of actual VBM Shapefile attributes

- Planned decision point: After `just build-vbm` produces first output, review layer attributes and decide which fields to retain.
- Factors:
  - Data size impact (more attributes = larger tiles)
  - Rendering utility (is the attribute useful for styling?)
  - Privacy/sensitivity (should certain fields be excluded?)

## VLCM Schema (To be determined)

**Status**: TBD — Pending inspection of actual VLCM Shapefile attributes

- Planned decision point: After `just build-vlcm` produces first output, review layer attributes and decide which fields to retain.
- Expected attributes may include:
  - `natural` source-layer: terrain type, slope, altitude indicators (likely)
  - `artificial` source-layer: infrastructure, construction-related classifications (likely)

## Refinement Process

1. **Inspect**: Run `just inspect` to see raw attributes in input ZIPs
2. **Build**: Run `just build-vlcm` / `just build-vbm` and generate initial tiles
3. **Validate**: Run `just validate` and inspect tile contents
4. **Review**: Examine which attributes appear in the PMTiles output
5. **Refine**: Update `scripts/build-vlcm.sh` and `scripts/build-vbm.sh` to filter/rename attributes as needed
6. **Document**: Complete this file with final schema decisions

## References

- MapLibre properties and feature state: https://maplibre.org/maplibre-style-spec/expressions/
- GeoJSON Feature Properties: https://tools.ietf.org/html/rfc7946#section-3.2
