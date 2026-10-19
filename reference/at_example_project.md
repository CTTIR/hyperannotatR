# A populated example project

A populated example project

## Usage

``` r
at_example_project(call = rlang::caller_env())
```

## Arguments

- call:

  The calling environment, for error reporting.

## Value

An
[annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
over the tissue example with one layer of three labelled regions.

## See also

Other example data:
[`at_example_image()`](https://cttir.github.io/hyperannotatR/reference/at_example_image.md),
[`at_example_path()`](https://cttir.github.io/hyperannotatR/reference/at_example_path.md),
[`at_example_session()`](https://cttir.github.io/hyperannotatR/reference/at_example_session.md)

Other projects:
[`at_add_layer()`](https://cttir.github.io/hyperannotatR/reference/at_add_layer.md),
[`at_add_roi()`](https://cttir.github.io/hyperannotatR/reference/at_add_roi.md),
[`at_layers()`](https://cttir.github.io/hyperannotatR/reference/at_layers.md),
[`at_project()`](https://cttir.github.io/hyperannotatR/reference/at_project.md),
[`at_remove_layer()`](https://cttir.github.io/hyperannotatR/reference/at_remove_layer.md),
[`at_remove_roi()`](https://cttir.github.io/hyperannotatR/reference/at_remove_roi.md),
[`at_rois()`](https://cttir.github.io/hyperannotatR/reference/at_rois.md),
[`at_summary()`](https://cttir.github.io/hyperannotatR/reference/at_summary.md),
[`at_validate()`](https://cttir.github.io/hyperannotatR/reference/at_validate.md)

## Examples

``` r
proj <- at_example_project()
at_rois(proj)
#> # A tibble: 3 × 15
#>   roi_id  layer label geom_type level source_level area_px centroid_x centroid_y
#>   <chr>   <chr> <chr> <chr>     <int>        <int>   <dbl>      <dbl>      <dbl>
#> 1 roi_00… regi… tumo… POLYGON       0            0   19600        190        220
#> 2 roi_00… regi… necr… POLYGON       0            0   72704        256        441
#> 3 roi_00… regi… stro… POLYGON       0            0   34200        390        125
#> # ℹ 6 more variables: n_vertices <int>, created <dttm>, modified <dttm>,
#> #   author <chr>, source <chr>, geometry <POLYGON>
```
