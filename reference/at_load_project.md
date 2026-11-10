# Load a project

Load a project

## Usage

``` r
at_load_project(path, call = rlang::caller_env())
```

## Arguments

- path:

  Path to a saved project `.rds`.

- call:

  The calling environment, for error reporting.

## Value

The
[annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).
Its image is reopened from the saved source descriptor; when the source
is missing, changed or ambiguous the annotations still load, pixel
access fails with a pointer to
[`at_relink_source()`](https://cttir.github.io/hyperannotatR/reference/at_relink_source.md),
and
[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md)
reports why. Warns if the file was written by a newer hyperannotatR.

## See also

Other io:
[`at_inspect_saved()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_saved.md),
[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md),
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

## Examples

``` r
lyr <- at_layer_add(at_layer("tissue", labels = "tumour"),
                    at_roi_rect(10, 10, 40, 40, label = "tumour"))
path <- tempfile(fileext = ".rds")
at_save_project(at_project(at_example_image("cube"), lyr), path)
proj <- at_load_project(path)
at_rois(proj)$label
#> [1] "tumour"
unlink(path)
```
