# Remove an ROI from a layer

Remove an ROI from a layer

## Usage

``` r
at_layer_remove(layer, id, call = rlang::caller_env())
```

## Arguments

- layer:

  An
  [annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- id:

  Single string ROI identifier.

- call:

  The calling environment, for error reporting.

## Value

A new
[annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
without the identified ROI. Warns if the ROI is not present and returns
the layer unchanged.

## See also

Other layers:
[`at_layer()`](https://cttir.github.io/hyperannotatR/reference/at_layer.md),
[`at_layer_add()`](https://cttir.github.io/hyperannotatR/reference/at_layer_add.md),
[`at_layer_n()`](https://cttir.github.io/hyperannotatR/reference/at_layer_n.md),
[`at_layer_rois()`](https://cttir.github.io/hyperannotatR/reference/at_layer_rois.md),
[`at_style()`](https://cttir.github.io/hyperannotatR/reference/at_style.md)

## Examples

``` r
lyr <- at_layer("tissue", labels = "tumour")
lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 10, 10, label = "tumour"))
lyr <- at_layer_add(lyr, at_roi_rect(20, 20, 30, 30, label = "tumour"))
first <- at_layer_rois(lyr)$roi_id[1]
at_layer_n(at_layer_remove(lyr, first))
#> [1] 1
```
