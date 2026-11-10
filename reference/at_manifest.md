# Session progress manifest with per-label counts

Session progress manifest with per-label counts

## Usage

``` r
at_manifest(session, call = rlang::caller_env())
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with `idx`, `entry_id`, `export_stem`, `name`, `path`, `status`,
`n_layers`, `n_rois`, and one integer column per label in the session
vocabulary giving its ROI count per image. `n_rois` counts the ROIs of
materialised projects (otherwise the manifest's stored count). A label
that clashes with one of the fixed column names gets a `label_` prefix.

## See also

Other sessions:
[`at_current()`](https://cttir.github.io/hyperannotatR/reference/at_current.md),
[`at_example_session()`](https://cttir.github.io/hyperannotatR/reference/at_example_session.md),
[`at_goto()`](https://cttir.github.io/hyperannotatR/reference/at_goto.md),
[`at_next()`](https://cttir.github.io/hyperannotatR/reference/at_next.md),
[`at_prev()`](https://cttir.github.io/hyperannotatR/reference/at_prev.md),
[`at_resume()`](https://cttir.github.io/hyperannotatR/reference/at_resume.md),
[`at_session()`](https://cttir.github.io/hyperannotatR/reference/at_session.md),
[`at_session_status()`](https://cttir.github.io/hyperannotatR/reference/at_session_status.md),
[`at_set_status()`](https://cttir.github.io/hyperannotatR/reference/at_set_status.md)

## Examples

``` r
sess <- at_session(rep(at_example_path("cube"), 2), labels = c("tumour", "stroma"))
sess <- at_batch_apply(sess, function(project, image, idx, ...) {
  at_add_roi(project, "annotations", at_roi_rect(5, 5, 20, 20, label = "tumour"))
}, progress = FALSE)
at_manifest(sess)[, c("idx", "status", "n_rois", "tumour", "stroma")]
#> # A tibble: 2 × 5
#>     idx status  n_rois tumour stroma
#>   <int> <chr>    <int>  <int>  <int>
#> 1     1 pending      1      1      0
#> 2     2 pending      1      1      0
```
