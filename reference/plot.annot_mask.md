# Plot a mask

Plot a mask

## Usage

``` r
# S3 method for class 'annot_mask'
plot(x, legend = TRUE, ...)
```

## Arguments

- x:

  An `annot_mask`.

- legend:

  Logical; show the fill legend. Default `TRUE`.

- ...:

  Ignored.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object (discrete fill from the legend colours, image orientation, axes
in pixel coordinates at the mask's level, framed to the whole grid; a
preview from
[`at_mask_preview()`](https://cttir.github.io/hyperannotatR/reference/at_mask_preview.md)
is drawn in its parent grid's coordinates). Not drawn; print it to
render.
