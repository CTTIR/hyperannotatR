# Pairwise ROI overlaps within a layer

Pairwise ROI overlaps within a layer

## Usage

``` r
at_rois_overlap(layer, call = rlang::caller_env(), image = NULL)
```

## Arguments

- layer:

  An
  [annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- call:

  The calling environment, for error reporting.

- image:

  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  defining actual pyramid dimensions; required for any nonzero ROI level
  because measurements are reported at level 0.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `id_a`, `id_b` (character), `overlap_px` (double, level-0
pixels), and `jaccard` (double). A 0-row tibble with these columns when
no ROIs overlap with positive area.

## See also

Other geometry:
[`at_check_containment()`](https://cttir.github.io/hyperannotatR/reference/at_check_containment.md),
[`at_check_geometry()`](https://cttir.github.io/hyperannotatR/reference/at_check_geometry.md),
[`at_clamp()`](https://cttir.github.io/hyperannotatR/reference/at_clamp.md),
[`at_fix_geometry()`](https://cttir.github.io/hyperannotatR/reference/at_fix_geometry.md),
[`at_flip_y()`](https://cttir.github.io/hyperannotatR/reference/at_flip_y.md),
[`at_roi_buffer()`](https://cttir.github.io/hyperannotatR/reference/at_roi_buffer.md),
[`at_roi_contains()`](https://cttir.github.io/hyperannotatR/reference/at_roi_contains.md),
[`at_roi_distance()`](https://cttir.github.io/hyperannotatR/reference/at_roi_distance.md),
[`at_roi_overlaps()`](https://cttir.github.io/hyperannotatR/reference/at_roi_overlaps.md),
[`at_roi_rescale()`](https://cttir.github.io/hyperannotatR/reference/at_roi_rescale.md),
[`at_roi_ring()`](https://cttir.github.io/hyperannotatR/reference/at_roi_ring.md),
[`at_roi_setops`](https://cttir.github.io/hyperannotatR/reference/at_roi_setops.md),
[`at_roi_simplify()`](https://cttir.github.io/hyperannotatR/reference/at_roi_simplify.md),
[`at_snap()`](https://cttir.github.io/hyperannotatR/reference/at_snap.md),
[`at_transform()`](https://cttir.github.io/hyperannotatR/reference/at_transform.md)

## Examples

``` r
lyr <- at_layer("tissue", labels = "tumour")
lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 10, 10, label = "tumour"))
lyr <- at_layer_add(lyr, at_roi_rect(5, 5, 15, 15, label = "tumour"))
at_rois_overlap(lyr)
#> # A tibble: 1 × 4
#>   id_a          id_b          overlap_px jaccard
#>   <chr>         <chr>              <dbl>   <dbl>
#> 1 roi_000000124 roi_000000125         25   0.143
```
