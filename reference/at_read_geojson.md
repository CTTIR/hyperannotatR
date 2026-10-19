# Read ROIs from a GeoJSON file

Read ROIs from a GeoJSON file

## Usage

``` r
at_read_geojson(
  path,
  layer_name = NULL,
  level = 0L,
  flip_y = FALSE,
  height = NULL,
  call = rlang::caller_env(),
  coordinate_level = NULL,
  legacy_levels = c("error", "recorded")
)
```

## Arguments

- path:

  Path to a GeoJSON file.

- layer_name:

  Layer name for the imported ROIs; taken from the features' `layer`
  property when `NULL`.

- level:

  Integer level to record when a feature has no `level` property.

- flip_y:

  Logical; invert the y-axis on read. Default `FALSE`.

- height:

  Image height in pixels, required when `flip_y = TRUE`.

- call:

  The calling environment, for error reporting.

- coordinate_level:

  Optional integer overriding every recorded `level` without scaling
  coordinates. Use only when the actual coordinate level is known, for
  example `0L` for legacy hyperannotatR exports that wrote level-0
  coordinates beside a nonzero source level. `NULL` (default) uses the
  schema and `legacy_levels` policy. Coordinates are never automatically
  repaired.

- legacy_levels:

  How to interpret files without the coordinate schema marker: `"error"`
  (default) rejects ambiguous nonzero recorded levels; `"recorded"`
  explicitly trusts those levels. Level-0 files remain unambiguous.

## Value

A named list of
[annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
objects (one per distinct `layer` property), or a single
[annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
when `layer_name` is supplied.

## Details

A FeatureCollection, a single Feature or a bare array of features is
accepted. Features without a geometry (`"geometry": null`) carry no
region and are skipped with a warning; any other document is refused
with an `at_validation_error` of code `INVALID_GEOJSON`.

## See also

Other io:
[`at_inspect_saved()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_saved.md),
[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md),
[`at_load_project()`](https://cttir.github.io/hyperannotatR/reference/at_load_project.md),
[`at_load_session()`](https://cttir.github.io/hyperannotatR/reference/at_load_session.md),
[`at_read_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_read_qupath.md),
[`at_read_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_read_rois_csv.md),
[`at_relink_source()`](https://cttir.github.io/hyperannotatR/reference/at_relink_source.md),
[`at_roi_from_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/hyperannotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/hyperannotatR/reference/at_save_session.md),
[`at_write_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_write_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_write_rois_csv.md)
