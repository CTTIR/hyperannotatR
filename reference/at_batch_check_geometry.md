# Check geometry across a whole session

Run
[`at_check_geometry()`](https://cttir.github.io/hyperannotatR/reference/at_check_geometry.md)
on every materialised project in the session and stack the reports. Like
[`at_check_geometry()`](https://cttir.github.io/hyperannotatR/reference/at_check_geometry.md)
(and unlike the assertion
[`at_validate()`](https://cttir.github.io/hyperannotatR/reference/at_validate.md)),
this returns a report rather than throwing.

## Usage

``` r
at_batch_check_geometry(session, call = rlang::caller_env())
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `image`, `roi_id`, `issue`, and `severity`. A 0-row tibble
when all geometry is valid.

## See also

[`at_check_geometry()`](https://cttir.github.io/hyperannotatR/reference/at_check_geometry.md)

Other batch:
[`at_batch_apply()`](https://cttir.github.io/hyperannotatR/reference/at_batch_apply.md),
[`at_export_all()`](https://cttir.github.io/hyperannotatR/reference/at_export_all.md),
[`at_summary_table()`](https://cttir.github.io/hyperannotatR/reference/at_summary_table.md)

## Examples

``` r
sess <- at_session(rep(at_example_path("cube"), 2), labels = "tumour")
# The second image gets an ROI reaching past its 128 x 128 pixel bounds.
sess <- at_batch_apply(sess, function(project, image, idx, ...) {
  roi <- if (idx == 2) at_roi_rect(100, 100, 150, 150, label = "tumour") else
    at_roi_rect(5, 5, 20, 20, label = "tumour")
  at_add_roi(project, "annotations", roi)
}, progress = FALSE)
at_batch_check_geometry(sess)
#> # A tibble: 1 × 4
#>   image        roi_id        issue         severity
#>   <chr>        <chr>         <chr>         <chr>   
#> 1 example_cube roi_000000005 out_of_bounds warning 
```
