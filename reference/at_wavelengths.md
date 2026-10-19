# Band centre wavelengths

Band centre wavelengths

## Usage

``` r
at_wavelengths(x, call = rlang::caller_env())
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A numeric vector of length `at_n_bands(x)` for a spectral image, or
`numeric(0)` when the image is not spectral.

## See also

[`at_is_spectral()`](https://cttir.github.io/hyperannotatR/reference/at_is_spectral.md)

Other images:
[`at_bands()`](https://cttir.github.io/hyperannotatR/reference/at_bands.md),
[`at_dims()`](https://cttir.github.io/hyperannotatR/reference/at_dims.md),
[`at_example_image()`](https://cttir.github.io/hyperannotatR/reference/at_example_image.md),
[`at_hsi_meta()`](https://cttir.github.io/hyperannotatR/reference/at_hsi_meta.md),
[`at_is_pyramidal()`](https://cttir.github.io/hyperannotatR/reference/at_is_pyramidal.md),
[`at_is_spectral()`](https://cttir.github.io/hyperannotatR/reference/at_is_spectral.md),
[`at_meta()`](https://cttir.github.io/hyperannotatR/reference/at_meta.md),
[`at_n_bands()`](https://cttir.github.io/hyperannotatR/reference/at_n_bands.md),
[`at_n_levels()`](https://cttir.github.io/hyperannotatR/reference/at_n_levels.md),
[`at_pixel_size()`](https://cttir.github.io/hyperannotatR/reference/at_pixel_size.md),
[`at_read_image()`](https://cttir.github.io/hyperannotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/hyperannotatR/reference/at_tile.md),
[`hyperannotatR-classes`](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
