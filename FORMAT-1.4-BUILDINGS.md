# Map tile file format (PMT), version 1.4: buildings by the water

THES-83 (the owner, 2026-10-21: "Have Panoptes roll the buildings and landmarks into its next firmware."). Version 1.4
adds one layer kind to `FORMAT.md` and `FORMAT-1.3-SYMBOLS-STREET-NAMES.md`; it changes nothing else.

## 1. What version 1.4 adds, and what it leaves alone

- **Layer kind 9, buildings:** polygons only (section 6 of `FORMAT.md`), no attribute records, no names, in files of
  their own beside a pack's other files.
- A file of kind 9 states minor version **4**; a reader refuses a kind 9 file that states less. Every other kind is
  written as before (a base, water or zones file as 1.0, roads and places as 1.1, land cover as 1.2, symbols and
  street names as 1.3).
- A reader that does not know kind 9 skips the file (`FORMAT.md` 7.7, "Readers of version 1.1"); a pack still holds
  at most 7 files of the kinds above 5 (`tools/assemble_pack.py` counts kind 9 with them).

## 2. Buildings (`layer_kind` 9)

| Class | What | From OpenStreetMap |
|---|---|---|
| 1 | A building | a closed way tagged `building` (any value but `no`), of 10 m² or more |
| 2 and up | Free | |

A reader draws the classes it knows and passes over every other class without an error. Buildings mapped as
multipolygon relations, and `building:part`, are not read.

**Only the buildings by the water.** All of North America's buildings would not fit a card, and a rider's map needs
the ones a rider sees from the water. A building is written when the zoom-14 tile of its first point, or one of the 8
tiles around it, holds a point of:

- a water area of 1 ha or more (the areas of `FORMAT.md` 7.2: `natural=water`, `waterway=riverbank`,
  `landuse=reservoir`; intermittent water and waste-water basins are not water here), or any way of a water
  multipolygon;
- a river or a canal centre line (`waterway=river|canal`; a stream or a ditch is not);
- a coastline (`natural=coastline`).

A zoom-14 tile is about 2.4 km across at the equator and 1.7 km at 45° north, so "by the water" is about 1 to 2.5 km.

### 2.1 The level

| Level | Tile zoom | Serves | Bits | Buffer | Tolerance | Classes |
|---|---|---|---|---|---|---|
| L0 | 14 | 15 to 16 | 14 | 64 | 1 m | 1 |

- Branding's style (pwca_logos `ux/PANOPTES_MAP_NEW_LAYERS_STYLE.md` section 2): buildings at zooms 15 and 16 only;
  fill `0x2C3C47`, line `0x364853`.
- A coverage grid: 1 where the file has buildings in the cell, 0 elsewhere. The value 2 and `full_class` are not
  used: an absent building tile draws nothing.
- Every tile is within the display's budget (12,000 features or parts, 100,000 points); a tile over it leaves out its
  smallest buildings first.
- `tolerance_dm` is 10. The string `str_layer` is `osm-buildings`.

### 2.2 What a display does with it (Branding's style, not part of the format)

The buildings are filled over land cover and under water, the shoreline, roads, symbols and names; never over water.
Nothing below zoom 15.

## 3. Test vector

| File | What |
|---|---|
| `tests/vectors/buildings.pmt`, `.txt` | Kind 9, 1.4: a house, an L-shaped building, a courtyard building (a hole), one running into the tile's buffer, and one of class 2, which a display passes over |

## 4. The builder

`python tools/build_pack.py <extract> <out_dir> --layer buildings --name <name>-buildings` (the passes: the water
relations and ways, their points, then a bit set of every node in the tiles by the water, then the buildings that
start on such a node). `tools/add_buildings.ps1` is the owner's one line: build, check, and a new card folder.
