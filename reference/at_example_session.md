# An example batch session

Copies the tissue example into a temporary directory `n` times so the
queue has real files to iterate.

## Usage

``` r
at_example_session(n = 5L, call = rlang::caller_env())
```

## Arguments

- n:

  Number of images in the queue. Default `5`.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

## See also

Other example data:
[`at_example_image()`](https://cttir.github.io/hyperannotatR/reference/at_example_image.md),
[`at_example_path()`](https://cttir.github.io/hyperannotatR/reference/at_example_path.md),
[`at_example_project()`](https://cttir.github.io/hyperannotatR/reference/at_example_project.md)

Other sessions:
[`at_current()`](https://cttir.github.io/hyperannotatR/reference/at_current.md),
[`at_goto()`](https://cttir.github.io/hyperannotatR/reference/at_goto.md),
[`at_manifest()`](https://cttir.github.io/hyperannotatR/reference/at_manifest.md),
[`at_next()`](https://cttir.github.io/hyperannotatR/reference/at_next.md),
[`at_prev()`](https://cttir.github.io/hyperannotatR/reference/at_prev.md),
[`at_resume()`](https://cttir.github.io/hyperannotatR/reference/at_resume.md),
[`at_session()`](https://cttir.github.io/hyperannotatR/reference/at_session.md),
[`at_session_status()`](https://cttir.github.io/hyperannotatR/reference/at_session_status.md),
[`at_set_status()`](https://cttir.github.io/hyperannotatR/reference/at_set_status.md)

## Examples

``` r
sess <- at_example_session(3)
at_session_status(sess)
#> # A tibble: 3 × 9
#>     idx entry_id              export_stem path  name  status project_path n_rois
#>   <int> <chr>                 <chr>       <chr> <chr> <chr>  <chr>         <int>
#> 1     1 entry_at_28cf4ec0827… entry_at_2… /tmp… imag… pendi… NA                0
#> 2     2 entry_at_28cf4ec0827… entry_at_2… /tmp… imag… pendi… NA                0
#> 3     3 entry_at_28cf4ec0827… entry_at_2… /tmp… imag… pendi… NA                0
#> # ℹ 1 more variable: modified <dttm>
```
