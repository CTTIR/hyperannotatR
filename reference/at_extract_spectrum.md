# Extract mean/median spectra for a spectral cube

Extract mean/median spectra for a spectral cube

## Usage

``` r
at_extract_spectrum(
  project,
  img = NULL,
  stat = "mean",
  layer = NULL,
  label = NULL,
  level = 0L,
  call = rlang::caller_env(),
  nonfinite = c("propagate", "omit", "error")
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

- stat:

  `"mean"` (default) or `"median"`.

- layer, label:

  Optional filters.

- level:

  Integer pyramid level. Default `0`.

- call:

  The calling environment, for error reporting.

- nonfinite:

  Policy for NA, NaN and infinite samples: `"propagate"` (default)
  returns NA statistics for any affected ROI/band; `"omit"` uses finite
  samples only; `"error"` aborts on selected nonfinite samples. `n`
  always counts selected pixels. A wholly invalid selection has NA
  statistics under omit (including sum); singleton sample SD is NA.

## Value

The long tibble of
[`at_extract()`](https://cttir.github.io/hyperannotatR/reference/at_extract.md),
restricted to spectral bands and sorted by ROI, declared unit,
wavelength, then band index. Values are not converted between units;
equal wavelengths retain band order.

## See also

Other extraction:
[`at_extract()`](https://cttir.github.io/hyperannotatR/reference/at_extract.md),
[`at_extract_pixels()`](https://cttir.github.io/hyperannotatR/reference/at_extract_pixels.md)

## Examples

``` r
cube <- at_example_image("cube")
proj <- at_project(cube, at_layer_add(at_layer("roi"),
                                      at_roi_circle(16, 16, 5, label = "roi")))
at_extract_spectrum(proj)
#> # A tibble: 40 × 12
#>    roi_id        layer label  band band_name wavelength unit  stat   value  n_px
#>    <chr>         <chr> <chr> <int> <chr>          <dbl> <chr> <chr>  <dbl> <int>
#>  1 roi_000000022 roi   roi       1 Band 1          450  nm    mean  32760.    80
#>  2 roi_000000022 roi   roi       2 Band 2          462. nm    mean  36680.    80
#>  3 roi_000000022 roi   roi       3 Band 3          473. nm    mean  40125.    80
#>  4 roi_000000022 roi   roi       4 Band 4          485. nm    mean  43501.    80
#>  5 roi_000000022 roi   roi       5 Band 5          496. nm    mean  46419.    80
#>  6 roi_000000022 roi   roi       6 Band 6          508. nm    mean  49054.    80
#>  7 roi_000000022 roi   roi       7 Band 7          519. nm    mean  50767.    80
#>  8 roi_000000022 roi   roi       8 Band 8          531. nm    mean  51994.    80
#>  9 roi_000000022 roi   roi       9 Band 9          542. nm    mean  52439.    80
#> 10 roi_000000022 roi   roi      10 Band 10         554. nm    mean  52137.    80
#> # ℹ 30 more rows
#> # ℹ 2 more variables: n_valid <int>, n_invalid <int>
```
