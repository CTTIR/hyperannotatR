# Read a mask into editable ROIs

Polygonise an existing mask file (e.g. Cellpose, StarDist, or QuPath
output, or a prior hyperannotatR export) into an editable
[annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).
Explicit metadata and legend/level arguments take precedence over
embedded RDS metadata, then the `<path>.legend.json` sidecar. Bitfields
polygonise each class membership. Legacy masks default to exclusive
values and zero background, recorded as `legacy-default`; incomplete
legacy bitfield legends require an explicit encoding override.
Malformed/future metadata and inconsistent dimensions fail rather than
silently discarding labels. Sampled previews or translated grids cannot
be polygonised as editable ROIs; import the original-resolution mask
with unit stride and zero origin.

## Usage

``` r
at_read_mask(
  path,
  level = NULL,
  connectivity = c(8L, 4L),
  simplify = 0,
  min_area = 0,
  legend = NULL,
  call = rlang::caller_env(),
  metadata = NULL
)
```

## Arguments

- path:

  Path to a mask file (TIFF, PNG, RDS, or NPY). NPY sidecar storage
  orientation is recovered automatically for polygonisation. PNG input
  must be unsigned 8/16-bit grayscale without palette, colour, alpha
  channels or `tRNS` transparency; original class codes are preserved.
  TIFF requires the raw `tiff` reader; PNG requires a `magick` build
  with exact grayscale capability.

- level:

  Integer pyramid level to record on the ROIs. `NULL` (default) uses the
  RDS mask or legend sidecar level, falling back to 0 for an external
  mask without level metadata. An explicit level overrides metadata.

- connectivity:

  Single finite whole number `8` (default) or `4`, including `8L`/`4L`.
  Eight-connectivity joins corner-touching pixels into one ROI;
  four-connectivity requires shared edges. Explicit vectors reject.

- simplify:

  Non-negative simplification tolerance for the polygons.

- min_area:

  Minimum polygon area in pixels to keep. Default `0`.

- legend:

  Optional legend tibble (`value`, `label`) overriding the embedded /
  sidecar / pixel-value labelling.

- call:

  The calling environment, for error reporting.

- metadata:

  Optional named list overriding semantic `mask_metadata` fields, such
  as `encoding`, `background`, or `source`. Nested grid fields merge
  with recovered metadata. Explicit `level` and `legend` take precedence
  over this list. Overrides do not resample pixels. Stored versioned
  metadata must be structurally valid before overrides are applied.

## Value

An
[annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
with one ROI per connected region. Recovered semantic metadata is
retained in `layer$meta$mask_metadata`, including empty layers.

## See also

[`at_write_mask()`](https://cttir.github.io/hyperannotatR/reference/at_write_mask.md),
[`at_mask()`](https://cttir.github.io/hyperannotatR/reference/at_mask.md)

Other masks:
[`at_mask()`](https://cttir.github.io/hyperannotatR/reference/at_mask.md),
[`at_mask_agreement()`](https://cttir.github.io/hyperannotatR/reference/at_mask_agreement.md),
[`at_mask_boundary()`](https://cttir.github.io/hyperannotatR/reference/at_mask_boundary.md),
[`at_mask_derive()`](https://cttir.github.io/hyperannotatR/reference/at_mask_derive.md),
[`at_mask_legend()`](https://cttir.github.io/hyperannotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/hyperannotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stats.md),
[`at_read_npy()`](https://cttir.github.io/hyperannotatR/reference/at_read_npy.md),
[`at_write_mask()`](https://cttir.github.io/hyperannotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/hyperannotatR/reference/at_write_masks.md),
[`at_write_npy()`](https://cttir.github.io/hyperannotatR/reference/at_write_npy.md)

## Examples

``` r
m <- at_mask(at_example_project(), "labelled")
f <- tempfile(fileext = ".tif")
at_write_mask(m, f)
at_read_mask(f)
#> Registered S3 method overwritten by 'stars':
#>   method                  from
#>   st_interpolate_aw.stars sf  
#> <annot_layer> file231538799060
#> ROIs: 3  |  labels: "tumour", "necrosis", and "stroma"
#> visible: TRUE  |  locked: FALSE  |  z: 1
```
