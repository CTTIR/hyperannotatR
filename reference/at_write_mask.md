# Write a mask to disk

Write a mask to disk

## Usage

``` r
at_write_mask(
  mask,
  path,
  format = c("tiff", "png", "rds"),
  bits = c(16L, 8L),
  legend = TRUE,
  overwrite = FALSE,
  call = rlang::caller_env()
)
```

## Arguments

- mask:

  An `annot_mask`.

- path:

  Output file path.

- format:

  `"tiff"` (default), `"png"` (8-bit only), or `"rds"` (full-fidelity
  `annot_mask`).

- bits:

  Single finite whole-number bit depth for TIFF: `16` (default) or `8`,
  including `16L`/`8L`. Explicit vectors are rejected.

- legend:

  Logical; also write a `<path>.legend.json` sidecar describing the
  mask. Default `TRUE`.

- overwrite:

  Logical; overwrite an existing file. Default `FALSE`.

- call:

  The calling environment, for error reporting.

## Value

The output path, invisibly.

## Details

TIFF exports preserve unsigned 8/16-bit codes; PNG exports are unsigned
8-bit only, regardless of `bits`. Samples must be finite integers in the
selected unsigned range; invalid samples reject before writing. TIFF
writing requires `tiff` or a capable `magick` build. PNG writing
requires `magick` with exact grayscale support. Missing exact conversion
capability produces an error rather than a quantized output. The
caller's explicit path is respected. Mask and legend are staged before
either is replaced; a preexisting sidecar also requires
`overwrite=TRUE`. Publication failure rolls back prior files. Concurrent
writers must be serialized.

## See also

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
[`at_read_npy()`](https://cttir.github.io/hyperannotatR/reference/at_read_npy.md),
[`at_write_masks()`](https://cttir.github.io/hyperannotatR/reference/at_write_masks.md),
[`at_write_npy()`](https://cttir.github.io/hyperannotatR/reference/at_write_npy.md)

## Examples

``` r
m <- at_mask(at_example_project(), "labelled")
f <- tempfile(fileext = ".tif")
at_write_mask(m, f)
```
