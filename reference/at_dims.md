# Image dimensions at a pyramid level

Return the pixel dimensions `c(width, height)` of an
[annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
at a given pyramid level.

## Usage

``` r
at_dims(x, level = 0L, call = rlang::caller_env())

# S3 method for class 'annot_image'
dim(x)
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- level:

  Integer pyramid level, `0` for full resolution. Must be in
  `0:(at_n_levels(x) - 1)`.

- call:

  The calling environment, for error reporting.

## Value

An integer vector of length 2, `c(width, height)`.

## Details

[`dim()`](https://rdrr.io/r/base/dim.html) on an
[annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
returns `c(width, height, bands)` at level 0. Note the order: width
first, unlike the `[y, x, band]` arrays returned by
[`at_tile()`](https://cttir.github.io/hyperannotatR/reference/at_tile.md),
so [`nrow()`](https://rdrr.io/r/base/nrow.html) gives the width.

## See also

[`at_n_levels()`](https://cttir.github.io/hyperannotatR/reference/at_n_levels.md),
[`at_is_pyramidal()`](https://cttir.github.io/hyperannotatR/reference/at_is_pyramidal.md)

Other images:
[`at_bands()`](https://cttir.github.io/hyperannotatR/reference/at_bands.md),
[`at_close_image()`](https://cttir.github.io/hyperannotatR/reference/at_close_image.md),
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
# Image handles come from at_read_image(); see the images vignette.
```
