# Extract per-pixel values under ROIs

Extract per-pixel values under ROIs

## Usage

``` r
at_extract_pixels(
  project,
  img = NULL,
  layer = NULL,
  level = 0L,
  bands = NULL,
  max_px = 1e+06,
  call = rlang::caller_env()
)
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- img:

  An
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md);
  defaults to the project's image. Supplying an alternate image asserts
  spatial registration on the same level-0 pixel grid. Its level-0
  extent must match; differing pyramid dimensions are handled using the
  alternate image's actual level dimensions.

- layer:

  Optional layer filter.

- level:

  Integer pyramid level. Default `0`.

- bands:

  Optional band indices; all bands by default.

- max_px:

  Maximum number of pixels to extract before aborting. Default `1e6`.

- call:

  The calling environment, for error reporting.

## Value

A long
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `roi_id`, `layer`, `label`, `x`, `y`, `band`, and `value`.
A 0-row tibble with these columns when nothing matches.

## See also

Other extraction:
[`at_extract()`](https://cttir.github.io/hyperannotatR/reference/at_extract.md),
[`at_extract_spectrum()`](https://cttir.github.io/hyperannotatR/reference/at_extract_spectrum.md)

## Examples

``` r
lyr <- at_layer_add(at_layer("tissue", labels = "tumour"),
                    at_roi_rect(10, 10, 20, 20, label = "tumour"))
proj <- at_project(at_example_image("cube"), lyr)
at_extract_pixels(proj, bands = 1:2)
#> # A tibble: 200 × 7
#>    roi_id        layer  label      x     y  band value
#>    <chr>         <chr>  <chr>  <dbl> <dbl> <int> <dbl>
#>  1 roi_000000026 tissue tumour    11    11     1 33073
#>  2 roi_000000026 tissue tumour    11    12     1 33300
#>  3 roi_000000026 tissue tumour    11    13     1 33412
#>  4 roi_000000026 tissue tumour    11    14     1 32984
#>  5 roi_000000026 tissue tumour    11    15     1 32311
#>  6 roi_000000026 tissue tumour    11    16     1 32858
#>  7 roi_000000026 tissue tumour    11    17     1 33694
#>  8 roi_000000026 tissue tumour    11    18     1 32458
#>  9 roi_000000026 tissue tumour    11    19     1 31874
#> 10 roi_000000026 tissue tumour    11    20     1 33421
#> # ℹ 190 more rows
```
