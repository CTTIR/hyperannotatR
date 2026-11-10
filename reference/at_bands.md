# Band (channel) table

Band (channel) table

## Usage

``` r
at_bands(x, call = rlang::caller_env())
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with one row per band and the columns:

- `index`:

  Band index, 1-based (integer).

- `name`:

  Band name (character); a default `"Band k"` when unnamed.

- `wavelength`:

  Centre wavelength (double); `NA` when not spectral or unknown for that
  band. Never interpolated.

- `unit`:

  Declared spectral coordinate unit (character); `NA` when not spectral
  or when the unit is unknown. Scalar metadata applies to all bands;
  per-band units are preserved without conversion.

- `fwhm`:

  Full width at half maximum in the wavelength unit (double); `NA` when
  the source does not declare it.

- `order`:

  Position of the band in file/manifest order (integer).

- `wavelength_status`:

  `"ok"`, `"missing"`, `"duplicate"` or `"non_numeric"` (character).

Always has `at_n_bands(x)` rows. The first four columns are unchanged
from hyperannotatR 0.1; the remaining columns were added in 0.2.0.

## See also

Other images:
[`at_close_image()`](https://cttir.github.io/hyperannotatR/reference/at_close_image.md),
[`at_dims()`](https://cttir.github.io/hyperannotatR/reference/at_dims.md),
[`at_example_image()`](https://cttir.github.io/hyperannotatR/reference/at_example_image.md),
[`at_hsi_meta()`](https://cttir.github.io/hyperannotatR/reference/at_hsi_meta.md),
[`at_image_capabilities()`](https://cttir.github.io/hyperannotatR/reference/at_image_capabilities.md),
[`at_is_pyramidal()`](https://cttir.github.io/hyperannotatR/reference/at_is_pyramidal.md),
[`at_is_spectral()`](https://cttir.github.io/hyperannotatR/reference/at_is_spectral.md),
[`at_meta()`](https://cttir.github.io/hyperannotatR/reference/at_meta.md),
[`at_n_bands()`](https://cttir.github.io/hyperannotatR/reference/at_n_bands.md),
[`at_n_levels()`](https://cttir.github.io/hyperannotatR/reference/at_n_levels.md),
[`at_pixel_size()`](https://cttir.github.io/hyperannotatR/reference/at_pixel_size.md),
[`at_read_image()`](https://cttir.github.io/hyperannotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/hyperannotatR/reference/at_tile.md),
[`at_wavelengths()`](https://cttir.github.io/hyperannotatR/reference/at_wavelengths.md),
[`hyperannotatR-classes`](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)

## Examples

``` r
at_bands(at_example_image("cube"))
#> # A tibble: 40 × 7
#>    index name    wavelength unit   fwhm order wavelength_status
#>    <int> <chr>        <dbl> <chr> <dbl> <int> <chr>            
#>  1     1 Band 1        450  nm       NA     1 ok               
#>  2     2 Band 2        462. nm       NA     2 ok               
#>  3     3 Band 3        473. nm       NA     3 ok               
#>  4     4 Band 4        485. nm       NA     4 ok               
#>  5     5 Band 5        496. nm       NA     5 ok               
#>  6     6 Band 6        508. nm       NA     6 ok               
#>  7     7 Band 7        519. nm       NA     7 ok               
#>  8     8 Band 8        531. nm       NA     8 ok               
#>  9     9 Band 9        542. nm       NA     9 ok               
#> 10    10 Band 10       554. nm       NA    10 ok               
#> # ℹ 30 more rows
```
