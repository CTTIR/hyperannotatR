# Overlay a mask on the canvas

Overlay a mask on the canvas

## Usage

``` r
at_canvas_set_overlay(proxy, mask, alpha = 0.5, call = rlang::caller_env())
```

## Arguments

- proxy:

  An `atcanvas_proxy`.

- mask:

  An `annot_mask`.

- alpha:

  Overlay opacity. Default `0.5`.

- call:

  The calling environment, for error reporting.

## Value

The proxy, invisibly.

## See also

Other shiny:
[`atCanvasOutput()`](https://cttir.github.io/hyperannotatR/reference/atCanvasOutput.md),
[`at_annotate()`](https://cttir.github.io/hyperannotatR/reference/at_annotate.md),
[`at_app()`](https://cttir.github.io/hyperannotatR/reference/at_app.md),
[`at_canvas()`](https://cttir.github.io/hyperannotatR/reference/at_canvas.md),
[`at_canvas_fit()`](https://cttir.github.io/hyperannotatR/reference/at_canvas_fit.md),
[`at_canvas_proxy()`](https://cttir.github.io/hyperannotatR/reference/at_canvas_proxy.md),
[`at_canvas_set_annotations()`](https://cttir.github.io/hyperannotatR/reference/at_canvas_set_annotations.md),
[`at_canvas_set_band()`](https://cttir.github.io/hyperannotatR/reference/at_canvas_set_band.md),
[`at_canvas_set_selection()`](https://cttir.github.io/hyperannotatR/reference/at_canvas_set_selection.md),
[`at_canvas_set_tool()`](https://cttir.github.io/hyperannotatR/reference/at_canvas_set_tool.md),
[`at_tile_source()`](https://cttir.github.io/hyperannotatR/reference/at_tile_source.md),
[`renderAtCanvas()`](https://cttir.github.io/hyperannotatR/reference/renderAtCanvas.md)

## Examples

``` r
lyr <- at_layer_add(at_layer("tissue", labels = "tumour"),
                    at_roi_rect(10, 10, 40, 40, label = "tumour"))
mask <- at_mask(at_project(at_example_image("cube"), lyr), "labelled")
# A mock session stands in for the browser; in an app use
# at_canvas_proxy("canvas") in the server function.
proxy <- at_canvas_proxy("canvas", session = shiny::MockShinySession$new())
at_canvas_set_overlay(proxy, mask, alpha = 0.4)
```
