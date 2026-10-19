# Read ROIs from a QuPath GeoJSON file

Reads QuPath 0.4+ exports (a native feature array, a FeatureCollection
or a single Feature) and the legacy hyperannotatR 0.1 dialect.
`classification.name` (or the joined `names` of a derived class, e.g.
`"Tumor: Positive"`) becomes the ROI label, the classification colour (a
current `color` RGB array or a legacy `colorRGB` integer) the layer
style colour, and features without a classification are labelled
`"unclassified"`. Everything else QuPath carries is kept, never
invented, under each ROI's `attributes$qupath`: the object id and type,
name, measurements (with explicit `value_state`), the image plane
(zero-based `c`, `z`, `t`; `c = NA` for all channels), metadata, a
nucleus geometry, and `roi_native = "ellipse"` with
`geometry_fidelity = "approximated"` for polygonised ellipses. A
hyperannotatR id stored in `metadata.annotatr_roi_id` is restored as the
ROI id; ordinary external ids are kept unchanged.

## Usage

``` r
at_read_qupath(
  path,
  layer_name = "qupath",
  level = 0L,
  call = rlang::caller_env(),
  coordinate_level = NULL,
  legacy_levels = c("error", "recorded")
)
```

## Arguments

- path:

  Path to a QuPath GeoJSON file.

- layer_name:

  Layer name for the imported ROIs. Default `"qupath"`.

- level:

  Integer fallback level for features without level metadata. Default
  `0` (standard full-resolution QuPath coordinates).

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

An
[annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

## Details

Input is validated strictly and keys are matched exactly: malformed
structure, contradictory duplicate fields (identical duplicates, which
QuPath 0.7.0 emits, are accepted), conflicting colours or object types
for a feature, conflicting colours for one label, and repeated ROI ids
are refused with an `at_validation_error` of code `INVALID_GEOJSON`.

## See also

Other io:
[`at_inspect_saved()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_saved.md),
[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md),
[`at_load_project()`](https://cttir.github.io/hyperannotatR/reference/at_load_project.md),
[`at_load_session()`](https://cttir.github.io/hyperannotatR/reference/at_load_session.md),
[`at_read_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_read_geojson.md),
[`at_read_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_read_rois_csv.md),
[`at_relink_source()`](https://cttir.github.io/hyperannotatR/reference/at_relink_source.md),
[`at_roi_from_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/hyperannotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/hyperannotatR/reference/at_save_session.md),
[`at_write_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_write_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_write_rois_csv.md)
