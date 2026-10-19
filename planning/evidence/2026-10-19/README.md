# Evidence 2026-10-19: release 0.3.0 after the rename to hyperannotatR

The 0.3.0 work ([2026-10-18 evidence](../2026-10-18/README.md)) was produced under the package's former name annotatR. On 2026-10-19 the maintainer renamed the package to hyperannotatR (`bbfd072`), and the work was applied on top of that rename and published as `77657d6`. The rename rules were those of `bbfd072`: `annotatR` became `hyperannotatR` in code, tests and documentation, including option names (`hyperannotatR.*`) and the app's resource prefix (`hyperannotatR-www`). Identifiers stored in files keep their spelling: `annotatR_version`, the coordinate schema `annotatR-pixel-level-v1`, the legacy QuPath keys `annotatR_roi_id` and `annotatR_coordinate_*` and the QuPath object-id seed `annotatR:roi:`, as do the lower-case contract identifiers (`annotatr-handoff-v1` and similar). Planning evidence and fixture data were not changed.

Before publishing, a read-only review of the integration (five reviewers, two skeptics per finding) found that the replacement had also renamed identifiers that files carry: the legacy QuPath metadata keys `annotatR_coordinate_schema` and `annotatR_coordinate_level`, written by the 2026-09 roadmap builds (a round-tripped file then lost its declared level silently), and, already in `bbfd072`, the seed of the deterministic QuPath object ids (`annotatR:roi:`), which would have given every re-exported ROI a new QuPath id. Both are restored, with regression tests that fail without the fix. The review also restored two QuPath provenance scripts byte for byte (their SHA-256 is recorded), corrected `cran-comments.md` and the citation metadata for the new name, and fixed "an hyperannotatR". Not changed here: qupflowR still lists `annotatR` in Suggests and Remotes, so its optional integration needs the new name.

Machine and toolchain as on 2026-10-18 (macOS 27.0.1 arm64, R 4.6.1, roxygen2 8.0.0, Chrome for Testing headless shell 156, Playwright 1.64.1, node 26). Every log here was produced on the tree of `77657d6`.

| File | Command (package root unless noted) | Result |
|---|---|---|
| `tests-full.log` | `NOT_CRAN=true` full suite (testthat `test_local`, silent reporter) | 81 files, 832 tests, 4981 expectations, 0 failures, 0 errors, 0 warnings, the same 9 named skips as on 2026-10-18 (two more tests: the restored legacy keys and object-id seed) |
| `rcmdbuild.log`, `rcmdcheck-00check.log`, `tarball-contents.txt` | clean export (`git archive` of the commit), `R CMD build --no-manual`, `_R_CHECK_FORCE_SUGGESTS_=false R CMD check --as-cran --no-manual hyperannotatR_0.3.0.tar.gz` | build exit 0; `Status: 1 NOTE`: *New submission*, and five URLs reported as possibly invalid because every request from this network timed out after 60 s (libcurl error 28), including the package's own GitHub URL, which answered at the time; tests, examples and vignettes OK; tarball 563 entries; the name conflict with Bioconductor `annotatr` is gone |
| `rcmdcheck-noremote-00check.log` | the same check with `_R_CHECK_CRAN_INCOMING_REMOTE_=false` (no network lookups) | `Status: OK` |
| `rcmdcheck-incoming-00check.log` | the same check on the renamed tree before the review fixes (09:21 UTC, network responsive) | `Status: 1 NOTE`, *New submission* only; no URL problems |
| `tests-browser-shinytest2.log` | `NOT_CRAN=true ANNOTATR_BROWSER_TESTS=true CHROMOTE_CHROME=<headless shell>`, `tests/testthat/test-app-browser.R` | 3 journeys, 22 expectations, 0 failures |
| `playwright-widget.log`, `playwright-app-journey.log`, `playwright-action-origin.log` | the runners in `tests/browser` against their R fixtures | exit 0, no page errors; the app journey includes the V10 scroll check |
| `node-tests.log` | `node --test tests/audit/widget.test.js tests/audit/keyboard.test.js` | 49 tests, 0 failures |
| `lint-house.log` | CTTIR house linters | identical to 2026-10-18 |
| `app-header.jpg` | headless Chrome on `at_app()` | the logo, stylesheet and keyboard script load from `hyperannotatR-www/`; brand and window title read hyperannotatR |

The browser-lane environment variable keeps its name (`ANNOTATR_BROWSER_TESTS`), as do the other `ANNOTATR_*` test variables.
