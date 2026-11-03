# Annotation revision token

A content revision for annotations: the SHA-256 of the canonical record
of every layer (name, labels, colours, z-order, visibility, lock) and
ROI (id, layer, label, level, geometry WKB, source, lock, review status,
plane and attributes). It changes whenever annotation content changes
and is independent of timestamps, authors, file paths and pixel data.
Partners pass it back as `expected_revision` to detect stale patches.

## Usage

``` r
at_annotation_revision(x, call = rlang::caller_env())
```

## Arguments

- x:

  An
  [annot_project](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md),
  [annot_layer](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md),
  or
  [annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  (combining every materialised project and the queue statuses).

- call:

  The calling environment, for error reporting.

## Value

A single string `"sha256:<64 hex>"`.

## See also

Other interop:
[`at_commit_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_commit_qupflowr.md),
[`at_export_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_export_qupflowr.md),
[`at_import_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_import_qupflowr.md),
[`at_interop_capabilities()`](https://cttir.github.io/hyperannotatR/reference/at_interop_capabilities.md),
[`at_interop_manifest()`](https://cttir.github.io/hyperannotatR/reference/at_interop_manifest.md),
[`at_stage_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_stage_qupflowr.md)

## Examples

``` r
proj <- at_project(at_example_image("cube"))
at_annotation_revision(proj)
#> [1] "sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"
```
