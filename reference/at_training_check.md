# Check a training dataset

Run independent checks on an exported training dataset: the integrity
inventory (schema, safe paths, symbolic links, sizes and SHA-256 hashes,
missing and unlisted files), the manifest schema, split leakage (every
group and image in exactly one split, every tile in its image's split),
mask dimensions and orientation, integer label range against the class
legend, the recorded overlap counts, and a mask -\> ROI -\> mask round
trip on a sample of tiles. When the source `x` is supplied, each sampled
tile is also re-rasterised from the annotations and compared exactly.
Tile files outside the verified inventory are never opened. A check that
cannot run on a malformed manifest is reported as `"fail"` rather than
raising an error; only an unsupported major version aborts
(`PROTOCOL_MISMATCH`).

## Usage

``` r
at_training_check(
  dataset,
  x = NULL,
  max_roundtrip_tiles = 20L,
  call = rlang::caller_env()
)
```

## Arguments

- dataset:

  Path of a dataset written by
  [`at_training_export()`](https://cttir.github.io/hyperannotatR/reference/at_training_export.md).

- x:

  Optional source
  [annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  or
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- max_roundtrip_tiles:

  Maximum number of tiles sampled for round trips.

- call:

  The calling environment, for error reporting.

## Value

A tibble of class `at_training_check` with `check`, `status` (`"ok"`,
`"warn"`, `"fail"`) and `detail`.

## See also

Other training:
[`at_training_export()`](https://cttir.github.io/hyperannotatR/reference/at_training_export.md),
[`at_training_import()`](https://cttir.github.io/hyperannotatR/reference/at_training_import.md)

## Examples

``` r
lyr <- at_layer_add(at_layer("tissue", labels = "tumour"),
                    at_roi_rect(10, 10, 40, 40, label = "tumour"))
proj <- at_project(at_example_image("cube"), lyr)
dest <- file.path(tempdir(), "training-check-example")
ds <- at_training_export(proj, dest, tile_size = 64, mask_format = "npy",
                         overwrite = TRUE)
at_training_check(dest, proj)
#> # A tibble: 8 × 3
#>   check              status detail                                              
#>   <chr>              <chr>  <chr>                                               
#> 1 integrity          ok     inventory verified                                  
#> 2 split_leakage      ok     1 groups, 1 images, no shared source across splits  
#> 3 mask_dimensions    ok     0 of 4 tiles with wrong or unreadable dimensions; 0…
#> 4 label_range        ok     0 of 4 tiles with codes outside the legend          
#> 5 overlap            ok     0 ambiguous (overlapping) pixels in included tiles  
#> 6 mask_roi_roundtrip ok     0 of 1 sampled tiles differ after mask -> ROI -> ma…
#> 7 source_agreement   ok     0 of 1 sampled tiles differ from re-rasterised anno…
#> 8 manifest_schema    ok     1.1                                                 
unlink(dest, recursive = TRUE)
```
