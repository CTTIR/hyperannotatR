# Create a batch annotation session

Create a batch annotation session

## Usage

``` r
at_session(
  paths,
  labels = character(),
  layers = NULL,
  out_dir = .session_out_dir(),
  autosave = TRUE,
  ...,
  call = rlang::caller_env()
)
```

## Arguments

- paths:

  Character vector of image file paths forming the queue.

- labels:

  Character vector of the global label vocabulary. Duplicates are
  dropped.

- layers:

  An
  [annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md),
  a list of them, or `NULL`. Applied as a template to every image
  visited.

- out_dir:

  Directory for autosave and exports. Defaults to a new, unique
  directory under [`tempdir()`](https://rdrr.io/r/base/tempfile.html),
  which R deletes when the process ends: pass a persistent directory to
  keep autosaved work. Separate sessions never share a default
  directory. A relative path is resolved against the working directory
  when the session is created.

- autosave:

  Logical; whether to autosave on annotation commits. Default `TRUE`.

- ...:

  Additional named session metadata.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
with a manifest over `paths`, all statuses `"pending"`, the cursor at
the first image, and projects not yet materialised.

## See also

[`at_next()`](https://cttir.github.io/hyperannotatR/reference/at_next.md),
[`at_current()`](https://cttir.github.io/hyperannotatR/reference/at_current.md),
[`at_resume()`](https://cttir.github.io/hyperannotatR/reference/at_resume.md)

Other sessions:
[`at_current()`](https://cttir.github.io/hyperannotatR/reference/at_current.md),
[`at_example_session()`](https://cttir.github.io/hyperannotatR/reference/at_example_session.md),
[`at_goto()`](https://cttir.github.io/hyperannotatR/reference/at_goto.md),
[`at_manifest()`](https://cttir.github.io/hyperannotatR/reference/at_manifest.md),
[`at_next()`](https://cttir.github.io/hyperannotatR/reference/at_next.md),
[`at_prev()`](https://cttir.github.io/hyperannotatR/reference/at_prev.md),
[`at_resume()`](https://cttir.github.io/hyperannotatR/reference/at_resume.md),
[`at_session_status()`](https://cttir.github.io/hyperannotatR/reference/at_session_status.md),
[`at_set_status()`](https://cttir.github.io/hyperannotatR/reference/at_set_status.md)

## Examples

``` r
# Build a session over the bundled example image copied several times:
# sess <- at_example_session(3)
```
