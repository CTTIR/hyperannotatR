# Jump to a specific image

Jump to a specific image

## Usage

``` r
at_goto(session, i, call = rlang::caller_env())
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md).

- i:

  Integer image index (1-based) within the queue.

- call:

  The calling environment, for error reporting.

## Value

A new
[annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
with the cursor at `i`.

## See also

Other sessions:
[`at_current()`](https://cttir.github.io/hyperannotatR/reference/at_current.md),
[`at_example_session()`](https://cttir.github.io/hyperannotatR/reference/at_example_session.md),
[`at_manifest()`](https://cttir.github.io/hyperannotatR/reference/at_manifest.md),
[`at_next()`](https://cttir.github.io/hyperannotatR/reference/at_next.md),
[`at_prev()`](https://cttir.github.io/hyperannotatR/reference/at_prev.md),
[`at_resume()`](https://cttir.github.io/hyperannotatR/reference/at_resume.md),
[`at_session()`](https://cttir.github.io/hyperannotatR/reference/at_session.md),
[`at_session_status()`](https://cttir.github.io/hyperannotatR/reference/at_session_status.md),
[`at_set_status()`](https://cttir.github.io/hyperannotatR/reference/at_set_status.md)

## Examples

``` r
sess <- at_session(rep(at_example_path("cube"), 3))
at_goto(sess, 3)
#> <annot_session>
#> images: 3  |  complete: 0  |  cursor: 3
#> out_dir: /tmp/RtmpTH8M04/hyperannotatR-session-33fd3157d7c  |  autosave: TRUE
```
