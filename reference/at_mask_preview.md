# Downsampled preview of a mask

Nearest-neighbour downsample only (interpolating a label mask would
invent labels that do not exist).

## Usage

``` r
at_mask_preview(mask, max_dim = 1024L, call = rlang::caller_env())
```

## Arguments

- mask:

  An `annot_mask`.

- max_dim:

  Integer maximum dimension of the preview. Default `1024`.

- call:

  The calling environment, for error reporting.

## Value

A downsampled `annot_mask` with membership-aware counts recomputed.
Metadata records the preview dimensions and sampling stride, its parent
grid, and the original source provenance. No full-resolution counts are
copied onto the sampled matrix.

## See also

Other masks:
[`at_mask()`](https://cttir.github.io/hyperannotatR/reference/at_mask.md),
[`at_mask_agreement()`](https://cttir.github.io/hyperannotatR/reference/at_mask_agreement.md),
[`at_mask_boundary()`](https://cttir.github.io/hyperannotatR/reference/at_mask_boundary.md),
[`at_mask_derive()`](https://cttir.github.io/hyperannotatR/reference/at_mask_derive.md),
[`at_mask_legend()`](https://cttir.github.io/hyperannotatR/reference/at_mask_legend.md),
[`at_mask_stack()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/hyperannotatR/reference/at_read_mask.md),
[`at_read_npy()`](https://cttir.github.io/hyperannotatR/reference/at_read_npy.md),
[`at_write_mask()`](https://cttir.github.io/hyperannotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/hyperannotatR/reference/at_write_masks.md),
[`at_write_npy()`](https://cttir.github.io/hyperannotatR/reference/at_write_npy.md)

## Examples

``` r
lyr <- at_layer_add(at_layer("tissue", labels = "tumour"),
                    at_roi_rect(10, 10, 40, 40, label = "tumour"))
mask <- at_mask(at_project(at_example_image("cube"), lyr), "labelled")
dim(at_mask_preview(mask, max_dim = 32))
#> [1] 32 32
```
