# Validate a project's invariants

Check that layer names are unique, ROI identifiers are unique across the
project, every ROI has one geometry at a pyramid level the image has,
and all geometries are valid.

## Usage

``` r
at_validate(project, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

The project, invisibly, if valid; otherwise an error describing the
violated invariant.

## See also

[`at_check_geometry()`](https://cttir.github.io/hyperannotatR/reference/at_check_geometry.md)

Other projects:
[`at_add_layer()`](https://cttir.github.io/hyperannotatR/reference/at_add_layer.md),
[`at_add_roi()`](https://cttir.github.io/hyperannotatR/reference/at_add_roi.md),
[`at_example_project()`](https://cttir.github.io/hyperannotatR/reference/at_example_project.md),
[`at_layers()`](https://cttir.github.io/hyperannotatR/reference/at_layers.md),
[`at_project()`](https://cttir.github.io/hyperannotatR/reference/at_project.md),
[`at_remove_layer()`](https://cttir.github.io/hyperannotatR/reference/at_remove_layer.md),
[`at_remove_roi()`](https://cttir.github.io/hyperannotatR/reference/at_remove_roi.md),
[`at_rois()`](https://cttir.github.io/hyperannotatR/reference/at_rois.md),
[`at_summary()`](https://cttir.github.io/hyperannotatR/reference/at_summary.md)

## Examples

``` r
proj <- at_validate(at_example_project())
```
