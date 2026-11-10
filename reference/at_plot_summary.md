# Plot a project summary

Plot a project summary

## Usage

``` r
at_plot_summary(project, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object of per-label ROI area distributions.

## See also

Other plots:
[`at_plot()`](https://cttir.github.io/hyperannotatR/reference/at_plot.md),
[`at_plot_image()`](https://cttir.github.io/hyperannotatR/reference/at_plot_image.md),
[`at_plot_mask()`](https://cttir.github.io/hyperannotatR/reference/at_plot_mask.md),
[`at_plot_overlay()`](https://cttir.github.io/hyperannotatR/reference/at_plot_overlay.md),
[`at_plot_project()`](https://cttir.github.io/hyperannotatR/reference/at_plot_project.md),
[`at_plot_spectrum()`](https://cttir.github.io/hyperannotatR/reference/at_plot_spectrum.md)

## Examples

``` r
lyr <- at_layer("tissue", labels = c("tumour", "stroma"))
lyr <- at_layer_add(lyr, at_roi_rect(10, 10, 40, 40, label = "tumour"))
lyr <- at_layer_add(lyr, at_roi_rect(50, 50, 60, 60, label = "tumour"))
lyr <- at_layer_add(lyr, at_roi_circle(90, 90, 15, label = "stroma"))
at_plot_summary(at_project(at_example_image("cube"), lyr))
```
