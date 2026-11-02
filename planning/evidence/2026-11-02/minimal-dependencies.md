# Minimal dependency examples and test fixtures

The preserved candidate-2 `depends-only-check.log` reports two example errors
(normal examples and `--run-donttest`), both first stopping at
`at_annotation_revision()` because its example reads the PNG tissue via
`at_example_project()`. The test run reports eight failures and one warning.
These are optional-reader assumptions in examples and fixtures, not failures
of the core ENVI runtime.

## Reproduction and fixes

`baseline-tests.log` repeats the three affected test files against the unchanged
installed candidate-2 package and an isolated dependency library built by R's
own `tools:::setRlibs(..., tests=TRUE)`. It reproduces six failed expectations,
two errors, and one warning. The warning comes from the summary-failure export
test: the PNG source cannot materialize, so it emits `1 export failed` before
the deliberately mocked summary failure.

`baseline-control-examples.log` exercises every Rd example topic independently,
including `donttest`, with core dependencies plus httpuv and its dependencies,
but without raster/TIFF/BioFormats readers. It confirms a second example defect:
the control-command example's queue navigation materializes a PNG and fails.
Both original annotation-revision and control-command examples fail in this
configuration (two errors, no warnings).

Source changes are restricted to roxygen and tests:

- Annotation revision, image accessor, app and control examples use the bundled
  ENVI cube. Applicable app/control guards are retained. Raster-specific project
  examples retain their magick guards. Multiplex reader documentation now names
  tiff as the required optional reader.
- Backend tests check real optional-reader availability and the missing-reader
  diagnostic. Core tile shape/range checks run on ENVI without a TIFF skip.
- Export contract tests use ENVI sessions while retaining every receipt,
  rollback, collision and failure-handling assertion.
- Legacy queue metadata/identifier migration runs without optional readers.
  Missing TIFF is checked explicitly; actual relink/fresh-process pixel checks
  run in a separate TIFF-guarded test. Legacy fixtures are unchanged.
- Exact roxygen2 8.0.0 regenerated only five affected Rd files.

## Verification

- `final-tests.log`: zero failures/errors/warnings, 80 passing expectations,
  eight accurate optional-TIFF skips in the three affected files.
- `final-full-tests.log`: zero failures/errors/warnings/skips, 133 passing
  expectations with installed optional readers.
- `final-examples.log`, `final-control-examples.log`,
  `final-full-examples.log`: all 83 Rd topics with example code examined in
  core-only, core-plus-httpuv, and fully provisioned environments respectively;
  zero errors and zero warnings in each. `examplesIf` guards are respected;
  `donttest` code is evaluated and `dontrun` code is not evaluated. The remaining
  72 Rd topics contain no examples and are recorded as such.
- `git diff --check` passed. No runtime code was changed in this repair.
- Independent integrity review found no material issue and confirmed that core
  export/accessor assertions and dependency-free legacy migration coverage were
  retained, with only TIFF pixel relinking guarded.

Run from the evidence directory after installing the source into
`readers/minimal/library` and copying current tests/fixtures under
`readers/minimal/tests`:

```sh
./run.sh Rscript readers/minimal/run-lane.R tests final
./run.sh Rscript readers/minimal/run-lane.R tests final full
./run.sh Rscript readers/minimal/run-lane.R examples final
./run.sh Rscript readers/minimal/run-lane.R examples final control
./run.sh Rscript readers/minimal/run-lane.R examples final full
```

The first harness iteration treated Rd topics without examples as missing R
files; those diagnostic logs/RDS remain suffixed `harness-first`. The corrected
harness records them as `NO_EXAMPLES`. A first test iteration also made an
incorrect additional assertion that source existence inspection would report
missing reader availability; that new assertion was removed after checking the
source-inspection contract. Its evidence remains suffixed `first`.

These targeted results do not substitute for the parent's final candidate-3
complete package checks.
