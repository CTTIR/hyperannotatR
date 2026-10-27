# List registered image backends

List registered image backends

## Usage

``` r
at_backend_list(call = rlang::caller_env())
```

## Arguments

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `name` (character), `description` (character), `extensions`
(character, comma-separated), and `available` (logical), plus
metadata_only and window_read (logical; NA when unknown). A 0-row tibble
with these columns when nothing is registered.

## See also

Other backends:
[`at_backend_detect()`](https://cttir.github.io/hyperannotatR/reference/at_backend_detect.md),
[`at_backend_get()`](https://cttir.github.io/hyperannotatR/reference/at_backend_get.md),
[`at_backend_register()`](https://cttir.github.io/hyperannotatR/reference/at_backend_register.md),
[`at_close_image()`](https://cttir.github.io/hyperannotatR/reference/at_close_image.md),
[`at_cubert_export_envi()`](https://cttir.github.io/hyperannotatR/reference/at_cubert_export_envi.md),
[`at_image_capabilities()`](https://cttir.github.io/hyperannotatR/reference/at_image_capabilities.md),
[`at_read_image()`](https://cttir.github.io/hyperannotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/hyperannotatR/reference/at_tile.md),
[`at_tivita_profile()`](https://cttir.github.io/hyperannotatR/reference/at_tivita_profile.md)

## Examples

``` r
at_backend_list()
#> # A tibble: 6 × 6
#>   name    description             extensions available metadata_only window_read
#>   <chr>   <chr>                   <chr>      <lgl>     <lgl>         <lgl>      
#> 1 cuvis   Cubert hyperspectral (… cu3, cu3s  FALSE     FALSE         FALSE      
#> 2 envi    ENVI header + binary c… hdr, dat,… TRUE      TRUE          TRUE       
#> 3 ometiff OME-TIFF and qptiff (R… ome.tif, … TRUE      FALSE         FALSE      
#> 4 raster  PNG, JPEG, and single-… png, jpg,… TRUE      FALSE         FALSE      
#> 5 tiff    Pyramidal / multi-dire… tif, tiff  TRUE      FALSE         FALSE      
#> 6 tivita  Diaspective Vision Tiv… dat, hdr   TRUE      TRUE          TRUE       
```
