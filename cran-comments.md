## Submission

This is a new submission.

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Maintainer: 'Raban Heller <raban.heller@uni-ulm.de>'
  New submission

  This is the expected note for a first submission.

## Test environments

* local: macOS 27.0.1 (aarch64-apple-darwin), R 4.6.1,
  `R CMD check --as-cran` on the built tarball, including the PDF manual
  (TinyTeX, TeX Live 2026) and the HTML manual validation (HTML Tidy 5.8.0).
  The Bioconductor package 'RBioFormats' (Suggests) needs a Java runtime
  configured for R and was not installed locally, so that run used
  `_R_CHECK_FORCE_SUGGESTS_=false`; its tests are skipped when it is absent.
* GitHub Actions (r-lib/actions v2, `--as-cran`): ubuntu-latest (R devel,
  release, oldrel-1), macos-latest (R release), windows-latest (R release),
  plus an informational ubuntu-latest oldrel-3 row.

## Notes

* The installed size is about 7.3 MB (R code 2.1 MB, vignettes 1.2 MB,
  example data 2.7 MB). The example data are small synthetic hyperspectral
  cubes and images in the formats the package reads (ENVI, TIFF, PNG); the
  examples, tests and vignettes need them to run offline. The source tarball
  is 4.2 MB.
* Tests take about two minutes; the longest app-server scenarios are skipped
  on CRAN.
* All suggested packages are used conditionally. Readers for optional image
  formats ('RBioFormats', 'tiff', 'terra', 'magick', 'png') are checked with
  `requireNamespace()` before use.
* The 'shiny' annotation app starts only in interactive sessions, and the
  example of the optional local control service runs in process without
  opening a network listener (`serve = FALSE`). Browser-based tests
  ('shinytest2', 'chromote') run only when explicitly enabled through an
  environment variable and are skipped on CRAN.
* Examples, tests and vignettes use bundled synthetic data, need no network
  access and write only to `tempdir()`.
