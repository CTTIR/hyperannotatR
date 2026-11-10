# Session summary statistics

Session summary statistics

## Usage

``` r
at_summary_table(
  session,
  by = c("image", "label", "layer"),
  call = rlang::caller_env()
)
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- by:

  Grouping: `"image"`, `"label"`, or `"layer"`.

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with the grouping key plus `n_rois`, `total_area_px`, `mean_area`, and
`sd_area`. Image summaries also include `entry_id`, so repeated display
names remain separate. A 0-row tibble when there are no ROIs.

## See also

Other batch:
[`at_batch_apply()`](https://cttir.github.io/hyperannotatR/reference/at_batch_apply.md),
[`at_batch_check_geometry()`](https://cttir.github.io/hyperannotatR/reference/at_batch_check_geometry.md),
[`at_export_all()`](https://cttir.github.io/hyperannotatR/reference/at_export_all.md)

## Examples

``` r
sess <- at_session(rep(at_example_path("cube"), 2), labels = "tumour")
sess <- at_batch_apply(sess, function(project, image, idx, ...) {
  at_add_roi(project, "annotations", at_roi_rect(5, 5, 5 + 10 * idx, 20, label = "tumour"))
}, progress = FALSE)
at_summary_table(sess, by = "label")
#> # A tibble: 1 × 5
#>   label  n_rois total_area_px mean_area sd_area
#>   <chr>   <int>         <dbl>     <dbl>   <dbl>
#> 1 tumour      2           450       225    106.
```
