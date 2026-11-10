# Add a layer to a project

Add a layer to a project

## Usage

``` r
at_add_layer(project, layer, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- layer:

  An
  [annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  with a name not already used in the project.

- call:

  The calling environment, for error reporting.

## Value

A new
[annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
with the layer added. ROIs in `layer` whose identifiers are missing,
already used in the project, or repeated within the layer are re-minted;
the first occurrence of each valid id is kept. The input is unchanged.

## See also

Other projects:
[`at_add_roi()`](https://cttir.github.io/hyperannotatR/reference/at_add_roi.md),
[`at_example_project()`](https://cttir.github.io/hyperannotatR/reference/at_example_project.md),
[`at_layers()`](https://cttir.github.io/hyperannotatR/reference/at_layers.md),
[`at_project()`](https://cttir.github.io/hyperannotatR/reference/at_project.md),
[`at_remove_layer()`](https://cttir.github.io/hyperannotatR/reference/at_remove_layer.md),
[`at_remove_roi()`](https://cttir.github.io/hyperannotatR/reference/at_remove_roi.md),
[`at_rois()`](https://cttir.github.io/hyperannotatR/reference/at_rois.md),
[`at_summary()`](https://cttir.github.io/hyperannotatR/reference/at_summary.md),
[`at_validate()`](https://cttir.github.io/hyperannotatR/reference/at_validate.md)

## Examples

``` r
proj <- at_project(at_example_image("cube"))
proj <- at_add_layer(proj, at_layer("tissue", labels = c("tumour", "stroma")))
at_layers(proj)
#> # A tibble: 1 × 6
#>   name   n_rois labels    visible locked     z
#>   <chr>   <int> <list>    <lgl>   <lgl>  <int>
#> 1 tissue      0 <chr [2]> TRUE    FALSE      1
```
