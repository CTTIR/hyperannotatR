# Inspect a saved checkpoint without modifying it

Validate a saved project or session file and report the state of its
image sources, without repairing anything or reading pixels.

## Usage

``` r
at_inspect_saved(path)
```

## Arguments

- path:

  A saved project or session RDS file.

## Value

A list with `valid` (logical), `class` (the saved object's class),
`issues` (character; why the file is invalid or ambiguous) and `sources`
(one
[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md)
report per stored project). Invalid or ambiguous structures are reported
without guessing repairs.

## See also

[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md),
[`at_load_session()`](https://cttir.github.io/hyperannotatR/reference/at_load_session.md)

Other io:
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
[`at_write_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_write_rois_csv.md)
