# Public maintenance evidence — 2 November 2026

Scope: hyperannotatR 0.3.1 candidate, from preserved merge `23cc5f9`.
Only public bundled and small synthetic data were used. No live annotation
workspace or private scientific dataset was read. The original checkout,
legacy wire identifiers, schema versions and pinned fixtures are preserved.

## Reproducible commands

Run these from a source checkout with the dependencies in DESCRIPTION, Node,
Java and optional Bio-Formats available. Browser runners additionally require
Chromium and Playwright; see `tests/browser/README.md`.

```sh
NOT_CRAN=true Rscript -e 'testthat::test_local(".")'
node --test tests/audit/widget.test.js tests/audit/keyboard.test.js
Rscript -e 'roxygen2::roxygenise()' # exactly roxygen2 8.0.0
R CMD build .
R CMD check --as-cran hyperannotatR_0.3.1.tar.gz
mkdir -p /tmp/hyperannotatR-library
R CMD INSTALL -l /tmp/hyperannotatR-library hyperannotatR_0.3.1.tar.gz
Rscript tests/qualification/installed-persistence.R /tmp/hyperannotatR-library
Rscript tests/qualification/installed-identity.R /tmp/hyperannotatR-library
Rscript -e 'covr::package_coverage()'
```

Use a clean export for the build; do not build an active checkout containing
ignored workbench data. The audited isolated tree contains only the public
source and evidence. Package build exclusions are verified on the tarball.
The exact host results and remaining gates are in `REPORT.md` and `results.json`.

## Evidence index

Paths below identify retained audit evidence; selected portable excerpts are
included in this directory. Absolute machine paths are redacted in excerpts.

| File | Command | Result |
| --- | --- | --- |
| `REPORT.md`, `results.json` | Combined final evidence review | Local criteria satisfied; external gates and limits explicit |
| `validation-summary.md` | Final full installed instrumentation | 5,504 passed, zero failures/warnings, eight named skips |
| `reader-review.md` | Bounded source/selection/lifecycle probes and focused R tests | Defects reproduced before repairs; 539 focused expectations pass |
| `integrity-review.md` | Commit, rollback, replay, startup, scoped key and mask probes | 1,096 focused expectations pass; handled-failure recovery verified |
| `app-review.md` | Real browser annotation, calibration, rejection/recovery and export | Drawing, five-repeat calibration, save/resume and export verified |
| `baseline-check.log` | Full `R CMD check --as-cran` on preserved baseline, after native setup | 0 errors, 0 warnings, 1 new-submission NOTE |
| `minimal-dependencies.md` | Core-only, core-plus-httpuv and full example/test lanes | All 83 example topics checked; affected behavior tests retained |
| `minimal-check-before.log` | First complete minimal-dependency check | Reproduced 3 errors; corrected optional-reader assumptions |
| `independent-review.md` | Separate code, real HTTP, browser and artifact review | Implementation review complete; final artifact results recorded separately |
| `site-review.md` | Static links plus Chromium navigation and visual checks | 186 pages and 9,721 local references pass |
| `manual-review.md` | Exact-source PDF layout, navigation and all-page review | Readable 139-page derivative verified; standard PDF preserved |
| `minimal-check.log` | Final minimal-dependency as-CRAN | 0 errors, 0 warnings, 1 new-submission NOTE; 3,420 expectations pass |
| `full-check.log` | Final full as-CRAN | 0 errors, 0 warnings, 1 new-submission NOTE; 5,462 expectations pass |
| `coverage.json` | Full installed test instrumentation | 91.87301%; 5,504 expectations pass; input hashes unchanged |
| `house-lint.log` | Pinned CTTIR report-only linter | 84 findings, with three deliberate test sentinels beyond baseline |
| `baseline-OME.log` | Real Bio-Formats reader/window tests on baseline | 302 expectations pass, no skips |

## Baseline and environment

The first full baseline check stopped because RBioFormats was unavailable.
That was an environment failure. An isolated rJava 1.0-18 / RBioFormats 1.12.0
installation using Java 17.0.21 and Bio-Formats 7.3.0 resolved it. The successful
baseline check includes PDF manual generation and normal incoming checks.
Global R configuration was not changed. Process-scoped JNI linker options were
needed to locate libjvm on this macOS host.

The initial R suite passed 5,113 expectations with nine skipped test rows
(ten named skip events) before Bio-Formats was available. Node passed 59/59.
Published upstream CI results apply to upstream commit 147c06e; they are not
results for this unpushed candidate.
