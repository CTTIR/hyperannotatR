# Read a NumPy `.npy` integer mask

Read a NumPy integer array (e.g. a ground-truth annotation mask) into a
lossless `annot_mask` – values are preserved exactly, including
composite bitfield codes. Use this (not
[`at_read_mask()`](https://cttir.github.io/hyperannotatR/reference/at_read_mask.md),
which polygonises) when the raw integer matrix is what you need, for
example to derive a training mask or compute agreement against another
mask.

## Usage

``` r
at_read_npy(
  path,
  level = NULL,
  transpose = FALSE,
  legend = NULL,
  call = rlang::caller_env(),
  metadata = NULL
)
```

## Arguments

- path:

  Path to a `.npy` file.

- level:

  Integer pyramid level to record. `NULL` (default) recovers the sidecar
  level, falling back to 0 without metadata. Explicit values override
  the sidecar declaration without resampling pixels.

- transpose:

  Logical; transpose the array on read, for files stored in the native
  cube order `(width, height)` = `[x, y]` (e.g. TIVITA/HyperGui masks)
  so the result lands in hyperannotatR's `[y, x]` convention. Default
  `FALSE` assumes the standard image convention `(height, width)`.

- legend:

  Optional legend tibble (`value`, `label`) overriding the sidecar /
  pixel-value labelling.

- call:

  The calling environment, for error reporting.

- metadata:

  Optional named list overriding semantic `mask_metadata` fields, such
  as `encoding`, `background`, or `source`. Nested grid fields merge;
  explicit `level` and `legend` take precedence. No pixels are
  resampled. Versioned declarations must be structurally valid before
  overrides apply.

## Value

An integer `annot_mask` preserving encoding, background, codebook, grid
and source metadata. Without encoding metadata, imports use exclusive
instance values and zero background with status `legacy-default`; signed
representable codes are preserved. A declared storage orientation must
match `transpose`, even for square arrays. Malformed sidecars are
rejected.

## Details

The header is validated strictly (NPY format versions 1-3, 2-D shapes,
scalar integer dtypes of 1, 2, 4 or 8 bytes in either byte order) and
the payload length is checked before reading; values that do not fit a
32-bit integer mask (including INT_MIN, R's missing-value code) are
refused, never truncated. Reads are bounded by option
`hyperannotatR.max_read_bytes` and headers by
`hyperannotatR.max_npy_header_bytes`.

## See also

[`at_write_npy()`](https://cttir.github.io/hyperannotatR/reference/at_write_npy.md),
[`at_read_mask()`](https://cttir.github.io/hyperannotatR/reference/at_read_mask.md)

Other masks:
[`at_mask()`](https://cttir.github.io/hyperannotatR/reference/at_mask.md),
[`at_mask_agreement()`](https://cttir.github.io/hyperannotatR/reference/at_mask_agreement.md),
[`at_mask_boundary()`](https://cttir.github.io/hyperannotatR/reference/at_mask_boundary.md),
[`at_mask_derive()`](https://cttir.github.io/hyperannotatR/reference/at_mask_derive.md),
[`at_mask_legend()`](https://cttir.github.io/hyperannotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/hyperannotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/hyperannotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/hyperannotatR/reference/at_read_mask.md),
[`at_write_mask()`](https://cttir.github.io/hyperannotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/hyperannotatR/reference/at_write_masks.md),
[`at_write_npy()`](https://cttir.github.io/hyperannotatR/reference/at_write_npy.md)

## Examples

``` r
m <- at_mask(at_example_project(), "labelled")
f <- tempfile(fileext = ".npy")
at_write_npy(m, f)
at_read_npy(f)
#> <annot_mask> labelled  |  512 x 512 px  |  level 0
#> values: 3
#> # A tibble: 3 × 6
#>   value label    layer   roi_id         n_px colour 
#>   <int> <chr>    <chr>   <chr>         <int> <chr>  
#> 1     1 tumour   regions roi_000000064 19600 #999999
#> 2     2 necrosis regions roi_000000065 72704 #E69F00
#> 3     3 stroma   regions roi_000000066 34200 #56B4E9
```
