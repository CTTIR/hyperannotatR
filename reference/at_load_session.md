# Load a session

Load a session

## Usage

``` r
at_load_session(path, call = rlang::caller_env())
```

## Arguments

- path:

  Path to a saved session `.rds`.

- call:

  The calling environment, for error reporting.

## Value

The
[annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).
A file written before sessions recorded queue entry identities gets one
per queue row. Stored projects are reopened lazily by
[`at_current()`](https://cttir.github.io/hyperannotatR/reference/at_current.md).
Warns if written by a newer hyperannotatR.

## See also

[`at_save_session()`](https://cttir.github.io/hyperannotatR/reference/at_save_session.md),
[`at_resume()`](https://cttir.github.io/hyperannotatR/reference/at_resume.md)

Other io:
[`at_inspect_saved()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_saved.md),
[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md),
[`at_load_project()`](https://cttir.github.io/hyperannotatR/reference/at_load_project.md),
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
