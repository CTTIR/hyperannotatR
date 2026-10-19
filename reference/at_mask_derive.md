# Derive a training mask from layer masks

Keep foreground state codes inside the requested anatomy class and
outside artefacts, using each mask's declared background and class
membership. An anatomy bitfield includes composite samples containing
the requested bit.

## Usage

``` r
at_mask_derive(
  state,
  anatomy,
  artefact = NULL,
  keep_label = "wound",
  background = NULL,
  call = rlang::caller_env(),
  alignment = c("legacy", "assert")
)
```

## Arguments

- state:

  An `annot_mask` of state (class) codes.

- anatomy:

  An `annot_mask` of anatomy codes, sharing `state`'s dimensions and
  level.

- artefact:

  Optional `annot_mask` (bitfield); pixels with any artefact bit set are
  dropped. `NULL` (default) applies no artefact exclusion.

- keep_label:

  The anatomy label whose region is kept (e.g. `"wound"`).

- background:

  Output background value. `NULL` (default) preserves the state mask's
  background. Must not collide with any state class code.

- call:

  The calling environment, for error reporting.

- alignment:

  `"legacy"` (default) validates declared source descriptors and grids;
  masks with only legacy metadata use a recorded legacy assumption.
  Modern masks with missing or conflicting provenance require
  `"assert"`, explicitly asserting registration without resampling.
  Dimensions must always agree. Entry IDs and runtime cache generations
  do not establish source compatibility. Combining the same object
  records `self-grid`.

## Value

An `annot_mask` retaining state encoding and the full state codebook,
with counts recomputed, zero counts for absent classes, and alignment
provenance recorded in `mask_metadata$derivation`.

## See also

[`at_mask()`](https://cttir.github.io/hyperannotatR/reference/at_mask.md),
[`at_mask_stack()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stack.md)

Other masks:
[`at_mask()`](https://cttir.github.io/hyperannotatR/reference/at_mask.md),
[`at_mask_agreement()`](https://cttir.github.io/hyperannotatR/reference/at_mask_agreement.md),
[`at_mask_boundary()`](https://cttir.github.io/hyperannotatR/reference/at_mask_boundary.md),
[`at_mask_legend()`](https://cttir.github.io/hyperannotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/hyperannotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/hyperannotatR/reference/at_read_mask.md),
[`at_read_npy()`](https://cttir.github.io/hyperannotatR/reference/at_read_npy.md),
[`at_write_mask()`](https://cttir.github.io/hyperannotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/hyperannotatR/reference/at_write_masks.md),
[`at_write_npy()`](https://cttir.github.io/hyperannotatR/reference/at_write_npy.md)

## Examples

``` r
proj <- at_example_project()
# A single-layer project derives trivially; the four-layer HSI workflow passes
# separate anatomy/state/artefact masks. See the masks vignette.
m <- at_mask(proj, "multiclass")
at_mask_derive(m, m, keep_label = at_mask_legend(m)$label[1])
#> <annot_mask> multiclass  |  512 x 512 px  |  level 0
#> values: 3
#> # A tibble: 3 × 6
#>   value label    layer   roi_id  n_px colour 
#>   <int> <chr>    <chr>   <chr>  <int> <chr>  
#> 1     1 tumour   regions NA     19600 #999999
#> 2     2 necrosis regions NA         0 #E69F00
#> 3     3 stroma   regions NA         0 #56B4E9
```
