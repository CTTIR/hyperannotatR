# Repair the geometry of a project

Apply
[`sf::st_make_valid()`](https://r-spatial.github.io/sf/reference/valid.html)
to invalid ROIs, drop duplicate consecutive vertices, re-orient holes
that wind like their exterior ring, and clip out-of-bounds geometry to
the image bounds (an intersection, so a polygon stays a polygon),
reporting what changed.

## Usage

``` r
at_fix_geometry(project, verbose = TRUE, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- verbose:

  Logical; whether to report repairs. Default `TRUE`.

- call:

  The calling environment, for error reporting.

## Value

The
[annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
with repaired geometry. Repairs are reported via
[`cli::cli_inform()`](https://cli.r-lib.org/reference/cli_abort.html)
when `verbose` is `TRUE`. Issues that cannot be repaired (zero area,
degenerate, empty, `NA` coordinates, or a clip that would leave nothing
inside the image) are left in place and reported.

## See also

[`at_check_geometry()`](https://cttir.github.io/hyperannotatR/reference/at_check_geometry.md)

Other geometry:
[`at_check_containment()`](https://cttir.github.io/hyperannotatR/reference/at_check_containment.md),
[`at_check_geometry()`](https://cttir.github.io/hyperannotatR/reference/at_check_geometry.md),
[`at_clamp()`](https://cttir.github.io/hyperannotatR/reference/at_clamp.md),
[`at_flip_y()`](https://cttir.github.io/hyperannotatR/reference/at_flip_y.md),
[`at_roi_buffer()`](https://cttir.github.io/hyperannotatR/reference/at_roi_buffer.md),
[`at_roi_contains()`](https://cttir.github.io/hyperannotatR/reference/at_roi_contains.md),
[`at_roi_distance()`](https://cttir.github.io/hyperannotatR/reference/at_roi_distance.md),
[`at_roi_overlaps()`](https://cttir.github.io/hyperannotatR/reference/at_roi_overlaps.md),
[`at_roi_rescale()`](https://cttir.github.io/hyperannotatR/reference/at_roi_rescale.md),
[`at_roi_ring()`](https://cttir.github.io/hyperannotatR/reference/at_roi_ring.md),
[`at_roi_setops`](https://cttir.github.io/hyperannotatR/reference/at_roi_setops.md),
[`at_roi_simplify()`](https://cttir.github.io/hyperannotatR/reference/at_roi_simplify.md),
[`at_rois_overlap()`](https://cttir.github.io/hyperannotatR/reference/at_rois_overlap.md),
[`at_snap()`](https://cttir.github.io/hyperannotatR/reference/at_snap.md),
[`at_transform()`](https://cttir.github.io/hyperannotatR/reference/at_transform.md)

## Examples

``` r
# An ROI reaching past the 128 x 128 pixel image is clipped to its bounds.
lyr <- at_layer_add(at_layer("tissue", labels = "tumour"),
                    at_roi_rect(100, 100, 150, 150, label = "tumour"))
proj <- at_project(at_example_image("cube"), lyr)
at_check_geometry(proj)
#> # A tibble: 1 × 4
#>   roi_id        issue         severity fixable
#>   <chr>         <chr>         <chr>    <lgl>  
#> 1 roi_000000028 out_of_bounds warning  TRUE   
fixed <- at_fix_geometry(proj)
#> ✔ Repaired 1 ROI.
at_check_geometry(fixed)
#> # A tibble: 0 × 4
#> # ℹ 4 variables: roi_id <chr>, issue <chr>, severity <chr>, fixable <lgl>
```
