# Write a project's ROIs as QuPath GeoJSON

The default `dialect = "qupath"` writes what QuPath 0.4 and later read
natively (verified with QuPath 0.7.0): `objectType`, `classification`
with an `[r, g, b]` colour, `isLocked` for locked ROIs, a deterministic
UUID per ROI as the feature id (QuPath replaces non-UUID ids; existing
UUIDs are kept), and hyperannotatR's own ROI id, layer, source and
stored level in `properties.metadata`. `dialect = "legacy"` writes the
hyperannotatR 0.1 form (`object_type`, signed `colorRGB`), which QuPath
still reads with a deprecation warning. Publication uses a staged
replacement.

## Usage

``` r
at_write_qupath(
  project,
  path,
  layer = NULL,
  level = 0L,
  overwrite = FALSE,
  dialect = c("qupath", "legacy"),
  call = rlang::caller_env()
)
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- path:

  Output file path.

- layer:

  Optional layer filter.

- level:

  Integer pyramid level for the coordinates and the `level` property.
  Default `0`, as QuPath expects; other levels are for consumers that
  explicitly support them.

- overwrite:

  Logical; overwrite an existing file. Default `FALSE`.

- dialect:

  `"qupath"` (default) or `"legacy"`.

- call:

  The calling environment, for error reporting.

## Value

The output path, invisibly.

## Details

Every feature records the pyramid level of its written coordinates as
the `level` property, the ROI's stored level as `source_level`, and the
marker `coordinate_schema = "annotatR-pixel-level-v1"`. QuPath keeps
only `metadata` through its own import and export, so the QuPath dialect
repeats the declaration there as `annotatr_coordinate_schema` and
`annotatr_coordinate_level`;
[`at_read_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_read_qupath.md)
restores ROIs at that level.

QuPath keeps one colour per classification name, so a label that has
different colours in different layers is written with the first colour
found for it.

## See also

[`at_read_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_read_qupath.md),
[`at_write_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_write_geojson.md)

Other io:
[`at_inspect_saved()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_saved.md),
[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md),
[`at_load_project()`](https://cttir.github.io/hyperannotatR/reference/at_load_project.md),
[`at_load_session()`](https://cttir.github.io/hyperannotatR/reference/at_load_session.md),
[`at_read_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_read_geojson.md),
[`at_read_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_read_qupath.md),
[`at_read_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_read_rois_csv.md),
[`at_relink_source()`](https://cttir.github.io/hyperannotatR/reference/at_relink_source.md),
[`at_roi_from_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/hyperannotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/hyperannotatR/reference/at_save_session.md),
[`at_write_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_write_geojson.md),
[`at_write_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_write_rois_csv.md)

## Examples

``` r
p <- tempfile(fileext = ".geojson")
at_write_qupath(at_example_project(), p)
```
