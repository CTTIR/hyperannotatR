# Rasterise ROIs to a mask ("Schablone")

Produce a binary, labelled, or multi-class integer mask from
annotations. This is the package's core output artifact.

## Usage

``` r
at_mask(
  x,
  type = c("binary", "labelled", "multiclass"),
  layer = NULL,
  label = NULL,
  level = 0L,
  background = 0L,
  touches = FALSE,
  dims = NULL,
  values = NULL,
  overlap = c("last", "first", "max", "min", "error", "bitor"),
  engine = c("stars", "terra"),
  call = rlang::caller_env(),
  image = NULL
)
```

## Arguments

- x:

  An
  [annot_roi](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md),
  [annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md),
  or
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- type:

  `"binary"` (a logical matrix), `"labelled"` (one integer id per ROI),
  or `"multiclass"` (one id per label class).

- layer:

  Optional layer name(s) to restrict to (projects only). Unknown names
  are an error.

- label:

  Optional label(s) to restrict to.

- level:

  Integer pyramid level at which to rasterise. Default `0`.

- background:

  Integer background value. Default `0`. Foreground codes must differ
  from background. Binary masks reject `1` (foreground), and normalize
  other accepted backgrounds to the stored logical `FALSE`/`0`.

- touches:

  Logical; see the coverage contract. Default `FALSE`.

- dims:

  Optional `c(width, height)`; taken from the image (projects) or the
  geometry bounding box otherwise, including containing cells for
  points.

- values:

  Optional named integer vector mapping labels to explicit class codes
  (e.g. `c(specular = 1L, blood = 2L, shadow = 4L)`), used only for
  `type = "multiclass"`. When `NULL` (default) codes follow first-seen
  label order: `1, 2, 3, ...`, or the single bits `1, 2, 4, ...` with
  `overlap = "bitor"`. Explicit bitfield codes must be distinct powers
  of two.

- overlap:

  How overlapping ROIs resolve: `"last"` (later z-order wins, the
  default), `"first"`, `"max"`, `"min"`, `"error"` (abort on any
  overlap), or `"bitor"` (bitwise-OR the overlapping class bits into a
  bitfield mask; `type = "multiclass"` or `"binary"` only, with
  `background = 0`; at most 31 classes).

- engine:

  `"stars"` or `"terra"` (if installed). Centre-based polygons and
  points use shared membership; other coverage uses the selected engine.

- call:

  The calling environment, for error reporting.

- image:

  Optional
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  for standalone ROIs or layers. Required when changing coordinate
  levels; dimensions alone do not define a scale. Projects always use
  their own image. Without `dims`, the image supplies the full mask
  extent at `level`.

## Value

An `annot_mask`: a matrix (logical for `"binary"`, otherwise integer)
with attributes `legend` (a tibble with columns `value`, `label`,
`layer`, `roi_id`, `n_px`, `colour`), `level`, `dims`, `mask_type`,
`source_project`, `mask_metadata` and `created`. An all-background mask
of the correct dimensions is returned when there are no ROIs. The
`mask_metadata` attribute has schema version 1 and records encoding
(`binary`, `instance`, `categorical`, or `bitfield`), background,
overlap policy, grid (dimensions, level, origin, stride), source
descriptor and entry provenance, and the complete label codebook.
Supplied `values` retain mapped-but-absent classes with zero counts.
Bitfields require unique positive single-bit codes and zero background;
category `3` is exclusive unless bitfield encoding is explicitly
declared.

## Details

**Pixel-coverage contract.** Pixel `(i, j)` covers the half-open square
`[j-1, j) x [i-1, i)` with `(0, 0)` at the top-left corner of the
top-left pixel; its centre is `(j - 0.5, i - 0.5)`. With
`touches = FALSE` (default) a pixel is included when its centre lies
inside the polygon. Boundary ties use the symbolic sample
`(x + epsilon, y + epsilon^2)` as `epsilon` tends to zero from above,
without a finite coordinate shift. Equivalently, scanline edges are
active on `[minY, maxY)` and crossing pairs fill `[left, right)`. Hole
rings exclude pixels by parity regardless of winding; `MULTIPOLYGON`
components combine by union. Thin polygons containing no selected
centres have empty masks. This rule is shared by both engines and all
overlap paths.

`POINT` and `MULTIPOINT` geometries select their half-open containing
cells: `(5, 5)` selects row 6, column 6. Extraction uses the same
membership and bounds. With `touches = TRUE`, polygon coverage uses the
selected engine's all-touched rasterisation; lines and other geometry
types also retain the selected engine's rasterisation behavior. Engine
equality is guaranteed for centre-based polygons and points. ROI
coordinates use the image convention (top-left origin, y down).

## See also

[`at_write_mask()`](https://cttir.github.io/hyperannotatR/reference/at_write_mask.md),
[`at_read_mask()`](https://cttir.github.io/hyperannotatR/reference/at_read_mask.md),
[`at_mask_stats()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stats.md)

Other masks:
[`at_mask_agreement()`](https://cttir.github.io/hyperannotatR/reference/at_mask_agreement.md),
[`at_mask_boundary()`](https://cttir.github.io/hyperannotatR/reference/at_mask_boundary.md),
[`at_mask_derive()`](https://cttir.github.io/hyperannotatR/reference/at_mask_derive.md),
[`at_mask_legend()`](https://cttir.github.io/hyperannotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/hyperannotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/hyperannotatR/reference/at_read_mask.md),
[`at_read_npy()`](https://cttir.github.io/hyperannotatR/reference/at_read_npy.md),
[`at_write_mask()`](https://cttir.github.io/hyperannotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/hyperannotatR/reference/at_write_masks.md),
[`at_write_npy()`](https://cttir.github.io/hyperannotatR/reference/at_write_npy.md)

## Examples

``` r
proj <- at_example_project()
m <- at_mask(proj, type = "multiclass")
table(as.integer(m))
#> 
#>      0      1      2      3 
#> 135640  19600  72704  34200 
```
