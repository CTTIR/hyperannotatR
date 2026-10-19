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
