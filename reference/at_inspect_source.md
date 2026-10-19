# Inspect an image source without changing annotations or reading pixels

Report whether the file an image (or project) was read from is still
available and unchanged, so a saved project can be reopened or relinked
deliberately.

## Usage

``` r
at_inspect_source(x)
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  or
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

## Value

A list with `status`, `path`, `backend`, `options` (the recorded reader
options) and `options_inferred` (`TRUE` for a legacy image whose options
were not recorded). `status` is `"available"`, `"missing"`, `"changed"`,
`"in_memory"` (pixels held in memory, no source file) or `"unresolved"`.
Size and modification time detect many source replacements, but are not
a content checksum. Composite sources also validate every declared
companion input, such as an ENVI header and payload.

## See also

[`at_relink_source()`](https://cttir.github.io/hyperannotatR/reference/at_relink_source.md),
[`at_inspect_saved()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_saved.md)

Other io:
[`at_inspect_saved()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_saved.md),
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
