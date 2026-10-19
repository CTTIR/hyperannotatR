## Status

hyperannotatR is not submitted to CRAN. This file records what a submission would
have to address.

## R CMD check results

Last full run: 2026-10-19, `R CMD check --as-cran --no-manual` on hyperannotatR
0.3.0 built from a clean export of the tracked sources (R 4.6.1, macOS 27.0.1
arm64, `_R_CHECK_FORCE_SUGGESTS_=false`).

0 errors | 0 warnings | 1 note

* NOTE: New submission.

The package was renamed from annotatR in 0.3.0. Under the old name, CRAN's
incoming feasibility check reported *conflicting package names*, because
`annotatR` differs only in case from the Bioconductor package `annotatr`; the
rename resolves this.

The evidence for these runs is kept outside the package sources in
`planning/evidence/2026-10-19/` (renamed package), `planning/evidence/2026-10-18/`
and `planning/evidence/2026-09-15/` (both under the former name).

## Test environments

* local: macOS 27.0.1 (arm64), R 4.6.1; Ubuntu 26.04, R 4.6.1
* GitHub Actions, through the shared CTTIR workflows: ubuntu-latest
  (R-devel, R-release, R-oldrel-1), macos-latest (R-release), windows-latest
  (R-release)

## Notes

Optional (`Suggests`) packages are guarded with `requireNamespace()` or
`@examplesIf`, so the package builds and loads without them. The browser,
loopback-HTTP, Cubert SDK and Bio-Formats test lanes need optional software
and run only when it is present; their skips name the missing prerequisite.
