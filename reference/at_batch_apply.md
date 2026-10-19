# Apply a function to every project in a session

Apply a function to every project in a session

## Usage

``` r
at_batch_apply(
  session,
  fn,
  ...,
  scope = "all",
  progress = TRUE,
  call = rlang::caller_env()
)
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- fn:

  A function `fn(project, image, idx, ...)` returning an
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- ...:

  Passed to `fn`.

- scope:

  `"all"` (default), `"complete"`, `"current"`, or `"flagged"`.

- progress:

  Logical; show a progress bar. Default `TRUE`.

- call:

  The calling environment, for error reporting.

## Value

The
[annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
with modified projects. An image whose project cannot be materialised,
or for which `fn` errors or does not return an
[annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md),
keeps its previous project; the failures are reported in one warning and
attached as the `"batch_errors"` attribute, a
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `idx`, `image` and `message`.

## See also

Other batch:
[`at_batch_check_geometry()`](https://cttir.github.io/hyperannotatR/reference/at_batch_check_geometry.md),
[`at_export_all()`](https://cttir.github.io/hyperannotatR/reference/at_export_all.md),
[`at_summary_table()`](https://cttir.github.io/hyperannotatR/reference/at_summary_table.md)
