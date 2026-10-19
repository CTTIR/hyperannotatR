# Read a tile from an image

The single, format-independent tile accessor. Returns a numeric array
with dimensions `[y, x, band]` — always three-dimensional, even for a
single band.

## Usage

``` r
at_tile(
  img,
  level = 0L,
  xrange = NULL,
  yrange = NULL,
  bands = NULL,
  call = rlang::caller_env()
)
```

## Arguments

- img:

  An
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- level:

  Integer pyramid level. Default `0`.

- xrange, yrange:

  Optional integer `c(min, max)` pixel ranges (1-based, inclusive) at
  `level`. `NULL` (default) means the full extent.

- bands:

  Optional integer band indices. `NULL` (default) means all bands.

- call:

  The calling environment, for error reporting.

## Value

A numeric array with dimensions `[y, x, band]`. An image whose pixel
handle was not saved is reopened from its source descriptor; a missing
or ambiguous source is an error with code `IMAGE_UNAVAILABLE` and a
changed source `IMAGE_CHANGED` (see
[`at_inspect_source()`](https://cttir.github.io/hyperannotatR/reference/at_inspect_source.md)
and
[`at_relink_source()`](https://cttir.github.io/hyperannotatR/reference/at_relink_source.md)).

## See also

Other images:
[`at_bands()`](https://cttir.github.io/hyperannotatR/reference/at_bands.md),
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
[`at_wavelengths()`](https://cttir.github.io/hyperannotatR/reference/at_wavelengths.md),
[`hyperannotatR-classes`](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)

Other backends:
[`at_backend_detect()`](https://cttir.github.io/hyperannotatR/reference/at_backend_detect.md),
[`at_backend_get()`](https://cttir.github.io/hyperannotatR/reference/at_backend_get.md),
[`at_backend_list()`](https://cttir.github.io/hyperannotatR/reference/at_backend_list.md),
[`at_backend_register()`](https://cttir.github.io/hyperannotatR/reference/at_backend_register.md),
[`at_close_image()`](https://cttir.github.io/hyperannotatR/reference/at_close_image.md),
[`at_cubert_export_envi()`](https://cttir.github.io/hyperannotatR/reference/at_cubert_export_envi.md),
[`at_image_capabilities()`](https://cttir.github.io/hyperannotatR/reference/at_image_capabilities.md),
[`at_read_image()`](https://cttir.github.io/hyperannotatR/reference/at_read_image.md),
[`at_tivita_profile()`](https://cttir.github.io/hyperannotatR/reference/at_tivita_profile.md)

## Examples

``` r
img <- at_example_image("tissue")
dim(at_tile(img, xrange = c(1, 16), yrange = c(1, 16)))
#> [1] 16 16  3
```
