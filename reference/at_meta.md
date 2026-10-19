# Image metadata

Image metadata

## Usage

``` r
at_meta(x, key = NULL, call = rlang::caller_env())
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- key:

  Optional single string. When supplied, the corresponding metadata
  element is returned; otherwise the whole metadata list is returned.

- call:

  The calling environment, for error reporting.

## Value

When `key` is `NULL`, a list of all metadata (including `source`,
`backend`, `dtype`, `pixel_unit`, and any backend-specific entries).
When `key` is supplied, the single element (or `NULL` if absent).

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
[`at_n_bands()`](https://cttir.github.io/hyperannotatR/reference/at_n_bands.md),
[`at_n_levels()`](https://cttir.github.io/hyperannotatR/reference/at_n_levels.md),
[`at_pixel_size()`](https://cttir.github.io/hyperannotatR/reference/at_pixel_size.md),
[`at_read_image()`](https://cttir.github.io/hyperannotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/hyperannotatR/reference/at_tile.md),
[`at_wavelengths()`](https://cttir.github.io/hyperannotatR/reference/at_wavelengths.md),
[`hyperannotatR-classes`](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
