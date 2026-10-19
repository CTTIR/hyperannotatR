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

  Optional
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  for accurate level-0 coordinate transforms.

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
