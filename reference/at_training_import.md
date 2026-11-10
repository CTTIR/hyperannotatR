# Import model predictions as staged annotations

Convert an integer prediction mask into ROIs and stage them against a
project; nothing is committed. The prediction must match the image
dimensions at `level`, contain only integers, and every non-background
value must be in `label_map`; otherwise the import aborts. Optional
per-pixel confidence below `min_confidence` is set to background first.
Model and prediction digests and the confidence policy are recorded on
every ROI, which starts as `review_status = "unreviewed"`. Reviewed or
locked annotations are never overwritten: with `replace = TRUE` they
become staged conflicts.

## Usage

``` r
at_training_import(
  x,
  predictions,
  label_map,
  level = 0L,
  source = "dnn_prediction",
  model = list(name = NA_character_, version = NA_character_, sha256 = NA_character_),
  confidence = NULL,
  min_confidence = NULL,
  layer = "predictions",
  replace = FALSE,
  stage = TRUE,
  call = rlang::caller_env()
)
```

## Arguments

- x:

  An
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- predictions:

  A mask file (TIFF/PNG/NPY), an `annot_mask`, or an integer matrix
  `[y, x]`.

- label_map:

  Named integer vector `label = code` (codes \>= 1; 0 is background).

- level:

  Pyramid level of the prediction grid.

- source:

  ROI source string. Default `"dnn_prediction"`.

- model:

  List with `name`, `version` and `sha256` of the model.

- confidence:

  Optional numeric matrix of per-pixel confidence.

- min_confidence:

  Optional threshold applied to `confidence` (which is then required).

- layer:

  Target layer name. Default `"predictions"`.

- replace:

  Logical; stage removal of existing unreviewed ROIs of `layer` not
  present in the prediction.

- stage:

  Logical; return an `at_staged_patch` (default) or, with `FALSE`, the
  prediction layer only.

- call:

  The calling environment, for error reporting.

## Value

An `at_staged_patch` (or an
[annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
when `stage = FALSE`) with attribute `prediction_digest`.

## See also

[`at_commit_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_commit_qupflowr.md)

Other training:
[`at_training_check()`](https://cttir.github.io/hyperannotatR/reference/at_training_check.md),
[`at_training_export()`](https://cttir.github.io/hyperannotatR/reference/at_training_export.md)

## Examples

``` r
proj <- at_project(at_example_image("cube"))
# A 128 x 128 prediction with two classes (0 is background).
pred <- matrix(0L, 128, 128)
pred[20:50, 20:50] <- 1L
pred[90:110, 60:100] <- 2L
patch <- at_training_import(proj, pred, label_map = c(tumour = 1L, stroma = 2L))
patch
#> <at_staged_patch> c861af52-d483-4b40-b6bc-ce4eddb26c72 (staged)
#>   create 2 | update 0 | unchanged 0 | delete 0 | conflict 0
#>   base sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945
#>   proposed sha256:0de7ec0ef2a821558cde199f5e2a7e98a54608c495d7b089f98554af33860327
at_training_import(proj, pred, label_map = c(tumour = 1L, stroma = 2L), stage = FALSE)
#> <annot_layer> predictions
#> ROIs: 2  |  labels: "tumour" and "stroma"
#> visible: TRUE  |  locked: FALSE  |  z: 1
```
