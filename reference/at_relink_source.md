# Explicitly relink or revalidate an image source

Point a saved image (or project) at its source file again, for example
after the file moved, or accept a source that changed since it was
saved. The replacement is read with the selected reader and must have
the same geometry; annotations are never changed.

## Usage

``` r
at_relink_source(x, path, backend = NULL, options = NULL)
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  or
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).
  Annotations and geometry are preserved.

- path:

  Replacement source path (may be the same path to revalidate).

- backend:

  Reader backend; defaults to the saved backend.

- options:

  Reader options as a list; defaults to the saved options.

## Value

The updated image or project. Dimensions, pyramid levels, band count and
wavelengths must agree. Relinking explicitly accepts the new source and
refreshes image metadata from the selected reader.

## See also

[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md)

Other io:
[`at_inspect_saved()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_saved.md),
[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md),
[`at_load_project()`](https://cttir.github.io/hyperannotatR/reference/at_load_project.md),
[`at_load_session()`](https://cttir.github.io/hyperannotatR/reference/at_load_session.md),
[`at_read_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_read_geojson.md),
[`at_read_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_read_qupath.md),
[`at_read_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_read_rois_csv.md),
[`at_roi_from_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/hyperannotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/hyperannotatR/reference/at_save_session.md),
[`at_write_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_write_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/hyperannotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/hyperannotatR/reference/at_write_rois_csv.md)
