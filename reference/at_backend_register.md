# Register an image backend

Backends are how hyperannotatR reads image formats. Each supplies
functions to read an image's metadata, fetch tiles, detect whether it
can read a file, and report whether its optional dependencies are
installed.

## Usage

``` r
at_backend_register(
  name,
  read_fn,
  tile_fn,
  detect_fn,
  available_fn,
  description = "",
  extensions = character(),
  call = rlang::caller_env(),
  capabilities = list(metadata_only = NA, window_read = NA, samples = "unqualified", io =
    "unknown"),
  close_fn = NULL
)
```

## Arguments

- name:

  Single string backend name (unique).

- read_fn:

  `function(path, ...)` returning an
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- tile_fn:

  `function(img, level, xrange, yrange, bands)` returning a numeric
  array `[y, x, band]`.

- detect_fn:

  `function(path)` returning `TRUE` if the backend can read the file.

- available_fn:

  `function()` returning `TRUE` if the backend's dependencies are
  installed.

- description:

  Single string human-readable description.

- extensions:

  Character vector of file extensions the backend handles.

- call:

  The calling environment, for error reporting.

- capabilities:

  Additive list declaring metadata_only, window_read, samples and io.
  Omitted capabilities are unknown. Readers can override these per image
  in meta\$capabilities.

- close_fn:

  Optional function(img) releasing runtime resources.

## Value

The registered `annot_backend`, invisibly.

## See also

[`at_backend_list()`](https://cttir.github.io/hyperannotatR/reference/at_backend_list.md),
[`at_read_image()`](https://cttir.github.io/hyperannotatR/reference/at_read_image.md)

Other backends:
[`at_backend_detect()`](https://cttir.github.io/hyperannotatR/reference/at_backend_detect.md),
[`at_backend_get()`](https://cttir.github.io/hyperannotatR/reference/at_backend_get.md),
[`at_backend_list()`](https://cttir.github.io/hyperannotatR/reference/at_backend_list.md),
[`at_close_image()`](https://cttir.github.io/hyperannotatR/reference/at_close_image.md),
[`at_cubert_export_envi()`](https://cttir.github.io/hyperannotatR/reference/at_cubert_export_envi.md),
[`at_image_capabilities()`](https://cttir.github.io/hyperannotatR/reference/at_image_capabilities.md),
[`at_read_image()`](https://cttir.github.io/hyperannotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/hyperannotatR/reference/at_tile.md),
[`at_tivita_profile()`](https://cttir.github.io/hyperannotatR/reference/at_tivita_profile.md)
