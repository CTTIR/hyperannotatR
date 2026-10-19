# Release an image handle

Drop an image's runtime pixel handle, calling the backend's `close_fn`
when it declares one.

## Usage

``` r
at_close_image(x)
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  or
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

## Value

The image or project with its runtime handle released; assign the
result. Later tile requests reopen the image from its source. Releasing
a retained pixel snapshot loses those pixels when the source has changed
or cannot be reopened. Built-in window readers open a connection per
read and hold no persistent connection.

## See also

Other images:
[`at_bands()`](https://cttir.github.io/hyperannotatR/reference/at_bands.md),
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

Other backends:
[`at_backend_detect()`](https://cttir.github.io/hyperannotatR/reference/at_backend_detect.md),
[`at_backend_get()`](https://cttir.github.io/hyperannotatR/reference/at_backend_get.md),
[`at_backend_list()`](https://cttir.github.io/hyperannotatR/reference/at_backend_list.md),
[`at_backend_register()`](https://cttir.github.io/hyperannotatR/reference/at_backend_register.md),
[`at_cubert_export_envi()`](https://cttir.github.io/hyperannotatR/reference/at_cubert_export_envi.md),
[`at_image_capabilities()`](https://cttir.github.io/hyperannotatR/reference/at_image_capabilities.md),
[`at_read_image()`](https://cttir.github.io/hyperannotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/hyperannotatR/reference/at_tile.md),
[`at_tivita_profile()`](https://cttir.github.io/hyperannotatR/reference/at_tivita_profile.md)

## Examples

``` r
cube <- at_close_image(at_example_image("cube"))
dim(at_tile(cube, xrange = c(1, 4), yrange = c(1, 4), bands = 1))
#> [1] 4 4 1
```
