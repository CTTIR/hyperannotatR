# Plot generic for hyperannotatR objects

Plot generic for hyperannotatR objects

## Usage

``` r
at_plot(x, ...)
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md),
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md),
  [annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md),
  or `annot_mask`.

- ...:

  Passed to the specific plot function. For layers, passed to
  [`at_layer_rois()`](https://cttir.github.io/hyperannotatR/reference/at_layer_rois.md):
  supply `image = img` for any nonzero stored ROI level. Layer plot
  geometry uses level-0 coordinates. The same image argument is
  supported by `ggplot2::autoplot(layer, image = img)`.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.

## See also

Other plots:
[`at_plot_image()`](https://cttir.github.io/hyperannotatR/reference/at_plot_image.md),
[`at_plot_mask()`](https://cttir.github.io/hyperannotatR/reference/at_plot_mask.md),
[`at_plot_overlay()`](https://cttir.github.io/hyperannotatR/reference/at_plot_overlay.md),
[`at_plot_project()`](https://cttir.github.io/hyperannotatR/reference/at_plot_project.md),
[`at_plot_spectrum()`](https://cttir.github.io/hyperannotatR/reference/at_plot_spectrum.md),
[`at_plot_summary()`](https://cttir.github.io/hyperannotatR/reference/at_plot_summary.md)

## Examples

``` r
at_plot(at_example_project())
```
