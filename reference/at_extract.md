# Extract summary statistics under ROIs

Compute per-band summary statistics of image values inside each ROI.
Reads one tile covering each ROI's clipped bounding box; an image-sized
bounding box can allocate an image-sized tile. Polygon centre membership
and point containing cells follow the pixel-coverage contract in
[`at_mask()`](https://cttir.github.io/hyperannotatR/reference/at_mask.md).
For example, point `(5, 5)` selects matrix row 6, column 6.

## Usage

``` r
at_extract(
  project,
  img = NULL,
  stat = "mean",
  layer = NULL,
  label = NULL,
  level = 0L,
  bands = NULL,
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

  One or more of `"mean"`, `"median"`, `"sd"`, `"min"`, `"max"`,
  `"sum"`, `"n"`, or `"all"` (every statistic).

- layer, label:

  Optional filters.

- level:

  Integer pyramid level. Default `0`.

- bands:

  Optional band indices; all bands by default.

- call:

  The calling environment, for error reporting.

- nonfinite:

  Policy for NA, NaN and infinite samples: `"propagate"` (default)
  returns NA statistics for any affected ROI/band; `"omit"` uses finite
  samples only; `"error"` aborts on selected nonfinite samples. `n`
  always counts selected pixels. A wholly invalid selection has NA
  statistics under omit (including sum); singleton sample SD is NA.

## Value

A long
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `roi_id`, `layer`, `label`, `band` (integer), `band_name`,
`wavelength` (`NA` when not spectral), `unit` (declared wavelength unit,
NA if unknown), `stat`, `value`, `n_px` (selected support), `n_valid`
(finite samples), and `n_invalid`. Empty selections produce zero rows.
Band order follows requested indices; wavelength values and units are
preserved, without implicit conversion. The `analysis` attribute records
policy, level, source, bands and limitations. Values come directly from
tiles, independently of display contrast. The raster backend itself uses
display conversion and cannot preserve original high-bit-depth samples;
raw TIFF/OME/ENVI readers have separate contracts.

## See also

[`at_extract_spectrum()`](https://cttir.github.io/hyperannotatR/reference/at_extract_spectrum.md),
[`at_extract_pixels()`](https://cttir.github.io/hyperannotatR/reference/at_extract_pixels.md)

Other extraction:
[`at_extract_pixels()`](https://cttir.github.io/hyperannotatR/reference/at_extract_pixels.md),
[`at_extract_spectrum()`](https://cttir.github.io/hyperannotatR/reference/at_extract_spectrum.md)

## Examples

``` r
proj <- at_example_project()
at_extract(proj, stat = "mean")
#> # A tibble: 9 × 12
#>   roi_id  layer label  band band_name wavelength unit  stat  value  n_px n_valid
#>   <chr>   <chr> <chr> <int> <chr>          <dbl> <chr> <chr> <dbl> <int>   <int>
#> 1 roi_00… regi… tumo…     1 R                 NA NA    mean  189.  19600   19600
#> 2 roi_00… regi… tumo…     2 G                 NA NA    mean   91.5 19600   19600
#> 3 roi_00… regi… tumo…     3 B                 NA NA    mean  165.  19600   19600
#> 4 roi_00… regi… necr…     1 R                 NA NA    mean  102.  72704   72704
#> 5 roi_00… regi… necr…     2 G                 NA NA    mean   81.6 72704   72704
#> 6 roi_00… regi… necr…     3 B                 NA NA    mean   76.5 72704   72704
#> 7 roi_00… regi… stro…     1 R                 NA NA    mean  174.  34200   34200
#> 8 roi_00… regi… stro…     2 G                 NA NA    mean  118.  34200   34200
#> 9 roi_00… regi… stro…     3 B                 NA NA    mean  163.  34200   34200
#> # ℹ 1 more variable: n_invalid <int>
```
