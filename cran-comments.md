## Status

hyperannotatR 0.3.1 is a locally validated, unsubmitted candidate. No CRAN,
Zenodo or hosted-platform acceptance is claimed.

## R CMD check results

2026-11-02: the exact source archive passed full `R CMD check --as-cran` on
R 4.6.1, macOS 27.0.1 arm64, with PDF manual generation, incoming checks and
all available suggested dependencies enabled. A separate
`_R_CHECK_DEPENDS_ONLY_=true` run passed against the same archive.

Both runs: 0 errors | 0 warnings | 1 note (New submission).

Full packaged tests: 5,462 passed, 13 named skips. Minimal-dependency tests:
3,420 passed, 108 optional-software/CRAN skips. Installed instrumentation ran
5,504 passing expectations with eight named skips and 91.87301% line coverage.
No test failures or warnings occurred in these final runs. Real browser and
HTTP checks ran separately; vendor/private-data lanes remain unqualified.

The first minimal check exposed optional-reader assumptions in examples and
test fixtures. Core examples and export tests now use bundled ENVI data;
reader-specific tests retain explicit prerequisites. All 83 example topics
also passed in core-only, core-plus-httpuv and full dependency environments.

## Test environments and release gates

The current candidate was tested locally on macOS only. The shared GitHub
workflow defines Linux R-devel/release/oldrel, macOS and Windows jobs, but this
candidate has not been pushed and those jobs have not run for it. Minimum
R 4.1 support, real CUVIS SDK inputs and partner-client qualification require
separate evidence before making those claims.

Evidence, limitations and the runnable first-use path are recorded in
`planning/evidence/2026-11-02/`. Earlier dated records remain unchanged.
The ordinary R-generated PDF manual has nine pre-existing line-wrapping clips;
a separately identified reading copy fixes layout only and has been visually
and structurally verified. The original check PDF is preserved.
