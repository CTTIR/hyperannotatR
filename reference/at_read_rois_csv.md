# Read ROIs from a CSV with WKT geometry

Read ROIs from a CSV with WKT geometry

## Usage

``` r
at_read_rois_csv(
  path,
  layer_name = "csv",
  call = rlang::caller_env(),
  coordinate_level = NULL,
  legacy_levels = c("error", "recorded")
)
```

## Arguments

- path:

  Path to a CSV with at least `label` and `geometry` (WKT) columns.
  Other columns (`roi_id`, `level`, `author`, `source`, `created`,
  `modified`) are used when present. Every column is read as text, so
  labels and ids such as `"T"`, `"007"` or `"NA"` are kept verbatim.
  `level` is the pyramid level of the WKT coordinates.

- layer_name:

  Layer name for the imported ROIs. Default `"csv"`.

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

  How to interpret files without the `coordinate_schema` marker:
  `"error"` (default) rejects ambiguous nonzero recorded levels;
  `"recorded"` explicitly trusts those levels. Level-0 files remain
  unambiguous.

## Value

An
[annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

## See also

Other io:
[`at_inspect_saved()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_saved.md),
[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md),
[`at_load_project()`](https://cttir.github.io/hyperannotatR/reference/at_load_project.md),
[`at_load_session()`](https://cttir.github.io/hyperannotatR/reference/at_load_session.md),
[`at_read_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_read_geojson.md),
[`at_read_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_read_qupath.md),
[`at_relink_source()`](https://cttir.github.io/hyperannotatR/reference/at_relink_source.md),
[`at_roi_from_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/hyperannotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/hyperannotatR/reference/at_save_session.md),
[`at_write_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_write_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_write_rois_csv.md)
