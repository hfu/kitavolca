#!/bin/bash
set -e

# Create test VLCM Shapefile (Polygon only)
echo "Creating test VLCM data..."
mkdir -p vlcm_test
cd vlcm_test

cat > vlcm.geojson << 'GJSON'
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {"name": "Natural terrain", "category": "natural", "id": 1},
      "geometry": {"type": "Polygon", "coordinates": [[[141.0, 42.0], [141.1, 42.0], [141.1, 42.1], [141.0, 42.1], [141.0, 42.0]]]}
    },
    {
      "type": "Feature",
      "properties": {"name": "Artificial area", "category": "artificial", "id": 2},
      "geometry": {"type": "Polygon", "coordinates": [[[141.15, 42.0], [141.25, 42.0], [141.25, 42.1], [141.15, 42.1], [141.15, 42.0]]]}
    }
  ]
}
GJSON

ogr2ogr -f "ESRI Shapefile" vlcm.shp vlcm.geojson 2>&1 | grep -v "^Warning" || true
cd ..

# Create test VBM Shapefile (Polygon only)
echo "Creating test VBM data..."
mkdir -p vbm_test
cd vbm_test

cat > vbm.geojson << 'GJSON'
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {"name": "Volcanic cone", "elevation": 1111, "scale": 5000},
      "geometry": {"type": "Polygon", "coordinates": [[[141.05, 42.05], [141.07, 42.05], [141.06, 42.08], [141.05, 42.05]]]}
    },
    {
      "type": "Feature",
      "properties": {"name": "Crater area", "scale": 5000},
      "geometry": {"type": "Polygon", "coordinates": [[[141.02, 42.02], [141.04, 42.02], [141.04, 42.04], [141.02, 42.04], [141.02, 42.02]]]}
    }
  ]
}
GJSON

ogr2ogr -f "ESRI Shapefile" vbm.shp vbm.geojson 2>&1 | grep -v "^Warning" || true
cd ..

echo "✓ Test data created"
ls -lhR vlcm_test vbm_test
