# Commit a staged partner patch

Apply an
[`at_stage_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_stage_qupflowr.md)
patch. Conflicting operations are never applied. The commit is
idempotent: repeating it with the same `idempotency_key` and the same
patch returns the original receipt without applying anything again,
while the same key with a different patch aborts with
`IDEMPOTENCY_CONFLICT`. When the patch targets a saved project file (or
`destination` names one), the file is re-read and its revision
re-checked immediately before writing; an existing file is only replaced
with `overwrite = TRUE`. A `<file>.commit.json` receipt records the key
across R sessions. The project and receipt are staged together; a failed
publication restores both previous files, or reports retained recovery
backups if restoration also fails. Writers to the same destination must
be serialised; this is not a cross-file transaction against process or
machine failure. A replay aborts with `REVISION_CONFLICT` if the saved
project has changed since that receipt was written. Reusing a cached key
for a different destination aborts with `IDEMPOTENCY_CONFLICT`.

## Usage

``` r
at_commit_qupflowr(
  x,
  idempotency_key = NULL,
  destination = NULL,
  overwrite = FALSE,
  call = rlang::caller_env()
)
```

## Arguments

- x:

  An `at_staged_patch`.

- idempotency_key:

  Optional client key; defaults to one derived from the patch id.

- destination:

  Optional project `.rds` path to write the committed project to;
  defaults to the patch's `target_path` when staged from a file.

- overwrite:

  Logical; allow replacing an existing project file.

- call:

  The calling environment, for error reporting.

## Value

An `at_commit_receipt`: a list with `state = "committed"`, `patch_id`,
`idempotency_key`, `previous_revision`, `new_revision`, `applied` and
`conflicts` (operation tibbles), `project`, `written` (path or `NA`),
`committed_at` and `replayed`.

## See also

[`at_stage_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_stage_qupflowr.md)

Other interop:
[`at_annotation_revision()`](https://cttir.github.io/hyperannotatR/reference/at_annotation_revision.md),
[`at_export_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_export_qupflowr.md),
[`at_import_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_import_qupflowr.md),
[`at_interop_capabilities()`](https://cttir.github.io/hyperannotatR/reference/at_interop_capabilities.md),
[`at_interop_manifest()`](https://cttir.github.io/hyperannotatR/reference/at_interop_manifest.md),
[`at_stage_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_stage_qupflowr.md)

## Examples

``` r
proj <- at_example_project()
partner <- at_layer_add(at_layer("regions"), at_roi_rect(10, 10, 40, 40, label = "tumour",
                                                         id = "partner-1"))
rc <- at_commit_qupflowr(at_stage_qupflowr(proj, partner))
rc$new_revision
#> [1] "sha256:5e2284fed48f5fa27babfbde08592ec9f33c1e00a227e22b72231c09e8aabaf7"
```
