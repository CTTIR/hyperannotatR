# Inspect the effective reading capabilities of an image

Report how an image's pixels are read: whether opening it reads metadata
only, whether tiles are read as windows from the file, what the samples
mean, and where they come from.

## Usage

``` r
at_image_capabilities(x)
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  or
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

## Value

A list with `metadata_only` and `window_read` (logical; `NA` when a
third-party backend does not declare them), `samples` (`"raw-scalar-v1"`
for stored values, `"display-converted-0-255"` for display conversions,
`"unqualified"` when undeclared) and `io` (`"binary"`, `"native"`,
`"eager"`, `"memory"` or `"unknown"`), plus an optional `lifecycle`. An
image whose handle holds decoded pixels reports memory access even for a
backend that normally reads windows.

## See also

Other images:
[`at_bands()`](https://cttir.github.io/hyperannotatR/reference/at_bands.md),
[`at_close_image()`](https://cttir.github.io/hyperannotatR/reference/at_close_image.md),
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
[`at_wavelengths()`](https://cttir.github.io/hyperannotatR/reference/at_wavelengths.md),
[`hyperannotatR-classes`](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)

Other backends:
[`at_backend_detect()`](https://cttir.github.io/hyperannotatR/reference/at_backend_detect.md),
[`at_backend_get()`](https://cttir.github.io/hyperannotatR/reference/at_backend_get.md),
[`at_backend_list()`](https://cttir.github.io/hyperannotatR/reference/at_backend_list.md),
[`at_backend_register()`](https://cttir.github.io/hyperannotatR/reference/at_backend_register.md),
[`at_close_image()`](https://cttir.github.io/hyperannotatR/reference/at_close_image.md),
[`at_cubert_export_envi()`](https://cttir.github.io/hyperannotatR/reference/at_cubert_export_envi.md),
[`at_read_image()`](https://cttir.github.io/hyperannotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/hyperannotatR/reference/at_tile.md),
[`at_tivita_profile()`](https://cttir.github.io/hyperannotatR/reference/at_tivita_profile.md)

## Examples

``` r
at_image_capabilities(at_example_image("cube"))$window_read
#> [1] TRUE
```
