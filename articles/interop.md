# Interoperability

![hyperannotatR logo](../reference/figures/logo.png)

Annotations are only useful if they can leave the tool that made them.
hyperannotatR stores every region of interest as a validated
simple-feature geometry in image pixel coordinates, with an explicit
pyramid level attached, which makes it straightforward to hand work off
to a viewer such as QuPath, to a GIS-flavoured GeoJSON consumer, or to a
Python segmentation pipeline, and to take the results back again.
Because the geometry model is the same one used internally, an export
followed by an import is a genuine round-trip rather than a lossy
approximation, and this vignette shows a live one for each format so you
can see that labels, identities, and coordinates survive intact.

A guiding principle runs through all four formats below: the coordinate
convention never changes silently. Coordinates are written in image
pixels unless you deliberately ask otherwise, so a polygon you exported
lands back on exactly the same pixels when you read it in.

We use the bundled example project throughout: three labelled rectangles
on a small tissue raster.

``` r

proj <- at_example_project()
at_rois(proj)[, c("roi_id", "layer", "label", "geom_type", "area_px")]
#> # A tibble: 3 × 5
#>   roi_id        layer   label    geom_type area_px
#>   <chr>         <chr>   <chr>    <chr>       <dbl>
#> 1 roi_000000001 regions tumour   POLYGON     19600
#> 2 roi_000000002 regions necrosis POLYGON     72704
#> 3 roi_000000003 regions stroma   POLYGON     34200
```

## GeoJSON

[`at_write_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_write_geojson.md)
serialises a project to a standard `FeatureCollection`. Each ROI becomes
one `Feature` whose `geometry` is the pixel-coordinate polygon and whose
`properties` carry the full hyperannotatR schema: `roi_id`, `layer`,
`label`, `level` (the level of the written coordinates), `source_level`,
`coordinate_schema`, `author`, `created`, `modified`, `source`, the
writing `annotatR_version`, and any free-form `attributes`. Keeping the
schema explicit is what lets a file survive a return trip.

``` r

gj <- tempfile(fileext = ".geojson")
at_write_geojson(proj, gj)
cat(readLines(gj)[1:22], sep = "\n")
#> {
#>   "type": "FeatureCollection",
#>   "features": [
#>     {
#>       "type": "Feature",
#>       "id": "roi_000000001",
#>       "geometry": {
#>         "type": "Polygon",
#>         "coordinates": [
#>           [
#>             [120, 150],
#>             [260, 150],
#>             [260, 290],
#>             [120, 290],
#>             [120, 150]
#>           ]
#>         ]
#>       },
#>       "properties": {
#>         "roi_id": "roi_000000001",
#>         "layer": "regions",
#>         "label": "tumour",
```

The `roi_id` is preserved verbatim, so an ROI keeps its identity across
the boundary and you can join exported measurements back to the original
annotation. Reading the file back with
[`at_read_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_read_geojson.md)
reconstructs one `annot_layer` per distinct `layer` property. We rebuild
a project on the original image and check that the labels came through
intact.

``` r

back <- at_read_geojson(gj)
imported <- at_project(proj$image, back[["regions"]])
identical(sort(at_rois(proj)$label), sort(at_rois(imported)$label))
#> [1] TRUE
```

### Coordinate levels and legacy imports

An ROI can be stored at any level of a pyramidal image, and the writers’
`level` argument transforms the coordinates to another level on the way
out. GeoJSON and QuPath exports write `level` matching their
coordinates, with the stored ROI level in `source_level` as provenance.
The `coordinate_schema = "annotatR-pixel-level-v1"` marker identifies
this contract. CSV exports always use level-0 coordinates and
`level = 0`. Image dimensions determine separate x and y scale factors;
no power-of-two pyramid is inferred. Vector geometry round trips use
floating-point precision (relative tolerance `1e-12`), so a region drawn
on an overview level comes back with the same level-0 area whichever
format carried it:

``` r

mx <- at_example_image("multiplex")
lp <- at_project(mx, at_layer_add(at_layer("regions"),
                                  at_roi_rect(10, 10, 40, 40, label = "a", level = 1L)))
gj1 <- tempfile(fileext = ".geojson")
at_write_geojson(lp, gj1)
csv1 <- tempfile(fileext = ".csv")
at_write_rois_csv(lp, csv1)
c(stored  = at_rois(lp)$area_px,
  geojson = at_rois(at_project(mx, at_read_geojson(gj1)[["regions"]]))$area_px,
  csv     = at_rois(at_project(mx, at_read_rois_csv(csv1, layer_name = "regions")))$area_px)
#>  stored geojson     csv 
#>    3600    3600    3600
```

Some older exports, including GeoJSON, CSV and QuPath files written by
hyperannotatR 0.2.0 and earlier, paired level-0 geometry with a nonzero
stored ROI level. Those files cannot be distinguished reliably from
valid nonzero-coordinate files, so readers reject an unmarked nonzero
recorded level by default with an `AMBIGUOUS_LEVEL` error. When the
actual coordinate level is known, pass it as `coordinate_level` (for
example `0L` for such hyperannotatR exports) to
[`at_read_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_read_geojson.md),
[`at_read_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_read_rois_csv.md)
or
[`at_read_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_read_qupath.md);
this overrides the level declaration without scaling coordinates. To
trust the recorded levels of legitimate foreign or legacy files, pass
`legacy_levels = "recorded"`. Use either only when the coordinate
convention is known; never guess a repair. Files without level metadata
default to level 0, or to the reader’s fallback `level`.

Mask imports, including NPY, recover the level from the RDS object or
the legend sidecar by default; an explicit `level` overrides it. Keep
the sidecar next to the raster, and for external masks without metadata
supply the level when it is not 0.

### The `flip_y` option

hyperannotatR’s convention is image orientation: the origin is top-left
and *y* increases downward. Many GIS tools instead expect *y* to
increase upward. Set `flip_y = TRUE` to write coordinates in that upward
convention; the y-axis is mirrored about the image height. If you write
flipped, you must read flipped, supplying the same `height` so the
inversion is undone:

``` r

h <- at_dims(proj$image)[2]
gj_flip <- tempfile(fileext = ".geojson")
at_write_geojson(proj, gj_flip, flip_y = TRUE)
regained <- at_read_geojson(gj_flip, flip_y = TRUE, height = h)
identical(sort(at_rois(at_project(proj$image, regained[["regions"]]))$centroid_y),
          sort(at_rois(proj)$centroid_y))
#> [1] TRUE
```

Leave `flip_y` at its default `FALSE` when exchanging with other
image-coordinate tools (including QuPath and hyperannotatR itself);
reach for it only when a downstream consumer explicitly wants a
cartesian, bottom-left origin.

## QuPath

QuPath reads and writes its own GeoJSON dialect. By default
[`at_write_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_write_qupath.md)
writes the form QuPath 0.4 and later read natively, checked against a
real QuPath 0.7.0 installation: `objectType` (`annotation`, or
`detection` for mask-derived ROIs), a `classification` with its `name`
(or the `names` of a derived class such as `"Tumor: Positive"`) and an
`[r, g, b]` `color`, and `isLocked` for locked ROIs. QuPath silently
replaces feature ids that are not UUIDs, so each ROI gets a
deterministic UUID (existing UUIDs are kept). The feature properties
carry `level`, `source_level` and `coordinate_schema`, but QuPath keeps
only `properties.metadata` through its own import and export, so
hyperannotatR repeats what it needs there as strings: `annotatr_roi_id`,
`annotatr_layer`, `annotatr_source`, `annotatr_level` (the stored ROI
level, as in hyperannotatR 0.2.0), `annotatr_coordinate_schema` and
`annotatr_coordinate_level`. QuPath 0.7.0 keeps these entries, so the
original id and the coordinate level come back; if another tool drops
the metadata, a non-UUID id cannot be recovered from the UUID.

[`at_read_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_read_qupath.md)
accepts a native feature array (QuPath’s default export), a
FeatureCollection or a single Feature, in the current dialect or the
legacy `object_type`/`colorRGB` form. It restores labels, colours and
ids, and keeps everything else QuPath carries under `attributes$qupath`:
object type, measurements with explicit `NaN`/infinity states, image
planes, cell nuclei, and a flag on ellipses that QuPath exported as
polygons. Features without a classification are imported as
`"unclassified"` rather than dropped. Input is validated strictly:
malformed structure, contradictory repeated fields (identical repeats,
which QuPath 0.7.0 emits, are accepted), conflicting colours or object
types, and repeated ROI ids are refused with an `INVALID_GEOJSON` error.

``` r

qp <- tempfile(fileext = ".geojson")
at_write_qupath(proj, qp)
feature <- jsonlite::read_json(qp)$features[[1]]
str(feature$properties[c("objectType", "classification", "metadata")], max.level = 2)
#> List of 3
#>  $ objectType    : chr "annotation"
#>  $ classification:List of 2
#>   ..$ name : chr "tumour"
#>   ..$ color:List of 3
#>  $ metadata      :List of 6
#>   ..$ annotatr_roi_id           : chr "roi_000000001"
#>   ..$ annotatr_layer            : chr "regions"
#>   ..$ annotatr_source           : chr "manual"
#>   ..$ annotatr_level            : chr "0"
#>   ..$ annotatr_coordinate_schema: chr "annotatR-pixel-level-v1"
#>   ..$ annotatr_coordinate_level : chr "0"
```

### The colour gotcha

Older QuPath versions, and hyperannotatR 0.1, stored a classification
colour as a **signed** 32-bit `colorRGB` integer packed as `0xFFRRGGBB`.
The `0xFF` alpha byte pushes most colours past `2^31`, so they wrap
around to negative values: the grey `#999999` serialises as `-6710887`.
hyperannotatR still reads that form and writes it with
`dialect = "legacy"`; the modular arithmetic is handled in both
directions. QuPath keeps a single colour per classification name, so
identical labels with different layer colours collapse to the first
colour it sees. Reading the file back recovers the hex colours onto the
layer style:

``` r

lyr <- at_read_qupath(qp)
lyr$style$colour
#>    tumour  necrosis    stroma 
#> "#999999" "#E69F00" "#56B4E9"
```

## Masks for Python

For pixel-level pipelines the exchange currency is a raster mask, not a
polygon.
[`at_write_mask()`](https://cttir.github.io/hyperannotatR/reference/at_write_mask.md)
writes an integer TIFF alongside a self-describing `<path>.legend.json`
sidecar that records the mask type, level, dimensions, and one entry per
class (`value`, `label`, `layer`, `roi_id`, `n_px`, `colour`). The
sidecar is what turns an anonymous grid of integers into something a
downstream model can interpret without guessing which value meant which
class, and it travels with the raster so the mapping is never lost.

``` r

m <- at_mask(proj, type = "labelled")
mp <- tempfile(fileext = ".tiff")
at_write_mask(m, mp)
cat(readLines(paste0(mp, ".legend.json"))[1:14], sep = "\n")
#> {
#>   "mask_metadata": {
#>     "schema_version": 1,
#>     "status": "declared",
#>     "encoding": "instance",
#>     "background": 0,
#>     "overlap": "last",
#>     "grid": {
#>       "dims": [512, 512],
#>       "level": 0,
#>       "origin": [0, 0],
#>       "stride": [1, 1]
#>     },
#>     "source": {
```

Here we used a `"labelled"` mask, where each ROI gets its own integer; a
`"binary"` mask collapses everything to foreground and background, and a
`"multiclass"` mask shares one integer per label. Whichever you choose,
the legend describes exactly what the pixels mean. On the Python side,
read the TIFF as an integer array and load the legend to map values back
to labels. This chunk is illustrative and is not run when the vignette
is built.

``` python
import json
import numpy as np
import tifffile

mask = tifffile.imread("mask.tiff")
with open("mask.tiff.legend.json") as f:
    legend = json.load(f)

labels = {e["value"]: e["label"] for e in legend["legend"]}
for value, label in labels.items():
    print(label, int(np.sum(mask == value)), "px")
```

## CSV and WKT

For spreadsheet users and pipelines that would rather not parse JSON,
[`at_write_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_write_rois_csv.md)
produces one row per ROI with the geometry in a Well-Known Text
`geometry` column, plus the metadata fields.
[`at_read_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_read_rois_csv.md)
parses any CSV with at least `label` and `geometry` columns back into a
layer.

``` r

csv <- tempfile(fileext = ".csv")
at_write_rois_csv(proj, csv)
lyr_csv <- at_read_rois_csv(csv, layer_name = "regions")
at_rois(at_project(proj$image, lyr_csv))[, c("label", "geom_type", "area_px")]
#> # A tibble: 3 × 3
#>   label    geom_type area_px
#>   <chr>    <chr>       <dbl>
#> 1 tumour   POLYGON     19600
#> 2 necrosis POLYGON     72704
#> 3 stroma   POLYGON     34200
```

Because WKT is understood by PostGIS, `sf`, Shapely, and most spatial
databases, the CSV is often the shortest path into a wider geospatial
stack.

## Export destinations and receipts

Batch and split-mask exports
([`at_export_all()`](https://cttir.github.io/hyperannotatR/reference/at_export_all.md),
[`at_write_masks()`](https://cttir.github.io/hyperannotatR/reference/at_write_masks.md)
and the app’s export) turn project, layer, ROI and class names into
safe, portable filename components and append deterministic suffixes to
collisions, including names that differ only in case. Display labels
stay in receipts and in the annotation and legend metadata. Exports
preflight the complete bundle, including sidecars and receipt files, and
reject symlinked paths inside the destination before writing. An
explicitly chosen single-file output path, as in
[`at_write_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_write_geojson.md),
can point to any directory.

A mask and its legend are staged before either is published. Existing
bundles are skipped unless replacement was requested, and a failed item
does not stop later items. The receipt has a row for every requested
image and format, with status `ok`, `error` or `skipped`, a message, the
paths, and byte counts for the output and its sidecar; `ok` means the
whole bundle was published. A failed publication restores the files it
replaced. Session exports rewrite `_export_manifest.csv` and
`_annotation_summary.csv` on every run; a failure to write them warns
and is kept in the receipt’s attributes without discarding the item
results.

Serialise exports and keep the destination stable while they run:
preflight and several renames are not a race-free transaction against
concurrent writers, crashes between renames, or symlinks changed during
the run.

For the complete list of import and export helpers, see the reference
index on the package website.
