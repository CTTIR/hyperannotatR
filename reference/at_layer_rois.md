# Layer ROI table

Layer ROI table

## Usage

``` r
at_layer_rois(layer, image = NULL, call = rlang::caller_env())
```

## Arguments

- layer:

  An
  [annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- image:

  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  defining actual pyramid dimensions. Required when any ROI is stored at
  a nonzero level; no scale is inferred without it.

- call:

  The calling environment, for error reporting.

## Value

An ROI table (see
[`at_rois()`](https://cttir.github.io/hyperannotatR/reference/at_rois.md)
for the column contract). A 0-row table with the same columns when the
layer has no ROIs.

## See also

Other layers:
[`at_layer()`](https://cttir.github.io/hyperannotatR/reference/at_layer.md),
[`at_layer_add()`](https://cttir.github.io/hyperannotatR/reference/at_layer_add.md),
[`at_layer_n()`](https://cttir.github.io/hyperannotatR/reference/at_layer_n.md),
[`at_layer_remove()`](https://cttir.github.io/hyperannotatR/reference/at_layer_remove.md),
[`at_style()`](https://cttir.github.io/hyperannotatR/reference/at_style.md)

## Examples

``` r
lyr <- at_layer_add(at_layer("tissue", labels = "tumour"),
                    at_roi_circle(20, 20, 5, label = "tumour"))
at_layer_rois(lyr)
#> # A tibble: 1 × 15
#>   roi_id  layer label geom_type level source_level area_px centroid_x centroid_y
#>   <chr>   <chr> <chr> <chr>     <int>        <int>   <dbl>      <dbl>      <dbl>
#> 1 roi_00… tiss… tumo… POLYGON       0            0    78.4         20         20
#> # ℹ 6 more variables: n_vertices <int>, created <dttm>, modified <dttm>,
#> #   author <chr>, source <chr>, geometry <POLYGON>
```
