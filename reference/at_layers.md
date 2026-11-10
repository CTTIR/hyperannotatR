# Layer summary table

Layer summary table

## Usage

``` r
at_layers(project, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with one row per layer and the columns `name` (character), `n_rois`
(integer), `labels` (list of character), `visible` (logical), `locked`
(logical), and `z` (integer). A 0-row tibble with these columns when the
project has no layers.

## See also

Other projects:
[`at_add_layer()`](https://cttir.github.io/hyperannotatR/reference/at_add_layer.md),
[`at_add_roi()`](https://cttir.github.io/hyperannotatR/reference/at_add_roi.md),
[`at_example_project()`](https://cttir.github.io/hyperannotatR/reference/at_example_project.md),
[`at_project()`](https://cttir.github.io/hyperannotatR/reference/at_project.md),
[`at_remove_layer()`](https://cttir.github.io/hyperannotatR/reference/at_remove_layer.md),
[`at_remove_roi()`](https://cttir.github.io/hyperannotatR/reference/at_remove_roi.md),
[`at_rois()`](https://cttir.github.io/hyperannotatR/reference/at_rois.md),
[`at_summary()`](https://cttir.github.io/hyperannotatR/reference/at_summary.md),
[`at_validate()`](https://cttir.github.io/hyperannotatR/reference/at_validate.md)

## Examples

``` r
lyr <- at_layer_add(at_layer("tissue", labels = "tumour"),
                    at_roi_rect(0, 0, 10, 10, label = "tumour"))
proj <- at_project(at_example_image("cube"), list(lyr, at_layer("artefact")))
at_layers(proj)
#> # A tibble: 2 × 6
#>   name     n_rois labels    visible locked     z
#>   <chr>     <int> <list>    <lgl>   <lgl>  <int>
#> 1 tissue        1 <chr [1]> TRUE    FALSE      1
#> 2 artefact      0 <chr [0]> TRUE    FALSE      1
```
