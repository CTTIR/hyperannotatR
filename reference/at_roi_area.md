# ROI area

ROI area

## Usage

``` r
at_roi_area(
  roi,
  level = 0L,
  units = c("px", "physical"),
  call = rlang::caller_env(),
  image = NULL
)
```

## Arguments

- roi:

  An
  [annot_roi](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- level:

  Integer pyramid level at which to express the area. Default `0`.

- units:

  Either `"px"` (pixels squared, the default) or `"physical"`. Physical
  area uses `image` calibration at level zero, in squared
  `image$pixel_unit`, and is invariant to reporting level. Unknown or
  pixel-only image calibration rejects. Without an image, legacy ROI
  `pixel_size=c(x,y)` is supported at stored level zero, in squared
  calibration units. Nonzero ROI levels require explicit
  `pixel_size_level` and `pixel_unit`; differing calibration and stored
  levels require an image for the geometric transform. Pixel sizes must
  be finite and positive. Geometric area is not raster support count.

- call:

  The calling environment, for error reporting.

- image:

  Optional
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  defining actual pyramid dimensions. Required when `level` differs from
  the ROI's stored level.

## Value

A numeric scalar area, or `NA_real_` for non-areal geometry (points,
lines).

## See also

Other rois:
[`at_roi_bbox()`](https://cttir.github.io/hyperannotatR/reference/at_roi_bbox.md),
[`at_roi_centroid()`](https://cttir.github.io/hyperannotatR/reference/at_roi_centroid.md),
[`at_roi_circle()`](https://cttir.github.io/hyperannotatR/reference/at_roi_circle.md),
[`at_roi_ellipse()`](https://cttir.github.io/hyperannotatR/reference/at_roi_ellipse.md),
[`at_roi_freehand()`](https://cttir.github.io/hyperannotatR/reference/at_roi_freehand.md),
[`at_roi_from_geojson()`](https://cttir.github.io/hyperannotatR/reference/at_roi_from_geojson.md),
[`at_roi_from_sf()`](https://cttir.github.io/hyperannotatR/reference/at_roi_from_sf.md),
[`at_roi_point()`](https://cttir.github.io/hyperannotatR/reference/at_roi_point.md),
[`at_roi_polygon()`](https://cttir.github.io/hyperannotatR/reference/at_roi_polygon.md),
[`at_roi_rect()`](https://cttir.github.io/hyperannotatR/reference/at_roi_rect.md)

## Examples

``` r
at_roi_area(at_roi_rect(0, 0, 10, 5, label = "a"))
#> [1] 50
```
