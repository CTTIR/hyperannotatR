# Agreement between two masks

Per-class Dice and Jaccard (IoU) plus an overall accuracy and Cohen's
kappa, comparing a reference mask `a` against a second mask `b` (e.g. a
hyperannotatR mask against a `.npy` ground truth, or two annotators).
Versioned metadata, grids, source provenance, encodings and semantic
codebooks are validated. Plain matrices are explicit-code legacy
categorical inputs and require finite representable integer values;
missing values are rejected.

## Usage

``` r
at_mask_agreement(
  a,
  b,
  background = 0L,
  labels = NULL,
  call = rlang::caller_env(),
  alignment = c("check", "assert"),
  code_alignment = c("strict", "by-label", "by-id")
)
```

## Arguments

- a:

  Reference `annot_mask` or integer matrix.

- b:

  Comparison `annot_mask` or integer matrix, same dimensions as `a`.

- background:

  Integer value treated as unlabeled/background and excluded from the
  per-class rows (still counted for overall accuracy/kappa). Defaults to
  declared metadata background, or `0` for plain matrices. Explicit
  values must agree with metadata; both inputs must share background.

- labels:

  Optional named vector or legend tibble (`value`, `label`) overriding
  display labels only. It cannot certify semantic codebook alignment.

- call:

  The calling environment, for error reporting.

- alignment:

  `"check"` (default) verifies shared grid/source metadata; `"assert"`
  records the caller's assertion of spatial alignment. Dimensions must
  always agree. Identical inputs permit a self-grid comparison without
  source descriptors; legacy pairs retain explicit-code/grid
  assumptions.

- code_alignment:

  `"strict"` (default) requires compatible code mappings; `"by-label"`
  explicitly maps categorical/binary/bitfield codes by unique semantic
  labels; `"by-id"` maps instance codes by stable unique `roi_id`.
  Remapping requires matching identity sets in both codebooks. Mixed
  plain matrices and annotated inputs require `alignment="assert"` and
  categorical encoding; plain codes then assert the annotated codebook.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with one row per class: `value`, `label`, `n_true`, `n_pred`, `tp`,
`fp`, `fn`, `dice`, `iou`. The `overall` attribute is a list of
`accuracy`, `kappa`, `mean_dice`, `mean_iou`, and `n_px`, `encoding`,
`alignment`, `code_alignment`, `background` and `nonfinite` (always
`"error"`). A `comparison` attribute retains validated input metadata
and legends for interpretation.

## Details

Categorical/binary classes use equality; bitfields use class
memberships, with overall accuracy measuring exact membership-set
agreement and kappa NA. Instance maps use stable unique ROI IDs, never
display class names. No spatial instance matching is inferred. Absent
classes retain rows with NA Dice/IoU; background-only accuracy is 1 and
kappa is NA (zero Cohen denominator). Mean Dice/IoU exclude absent
classes and are NA if none are defined.

## See also

[`at_mask()`](https://cttir.github.io/hyperannotatR/reference/at_mask.md),
[`at_read_npy()`](https://cttir.github.io/hyperannotatR/reference/at_read_npy.md)

Other masks:
[`at_mask()`](https://cttir.github.io/hyperannotatR/reference/at_mask.md),
[`at_mask_boundary()`](https://cttir.github.io/hyperannotatR/reference/at_mask_boundary.md),
[`at_mask_derive()`](https://cttir.github.io/hyperannotatR/reference/at_mask_derive.md),
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
m <- at_mask(at_example_project(), "multiclass")
ag <- at_mask_agreement(m, m)
attr(ag, "overall")$kappa
#> [1] 1
```
