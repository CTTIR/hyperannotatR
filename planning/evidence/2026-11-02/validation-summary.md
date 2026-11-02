# Final integrity documentation and validation — 2 November 2026

The guides now match the completed repairs:

- `vignettes/partner-interop.Rmd`: saved and in-memory replay semantics,
  destination/revision checks, paired project/receipt publication and recovery,
  limits under crashes/concurrent writers, pixel persistence, failed-start
  cleanup, per-instance control keys and negotiated-root companion checks.
- `vignettes/masks.Rmd`: positive/finite dimensions and ceiling semantics,
  integer indexing checks, the existing byte-limit option with a 32-byte-per-pixel
  estimate, and explicit exclusions for RSS/native/geometry/aggregate stacks.

Both guides received independent review against the implementation. The reader
owner supplied the final control companion-boundary paragraph. No source,
metadata or fixture bytes were edited in this documentation task. Subsequent
source/example corrections were made by their assigned owners and reviewed here.

## Frozen validation

Run from the external evidence directory; `W` is the isolated public worktree.
`run.sh` selects the audit R libraries. The final coverage run began after both
source owners froze their runtime, examples and tests. The complete R/test file
inventory and its hashes matched again after the instrumented suite finished.
The run completed at 18:35:53 UTC; testthat 3.3.2 was active.

| File | Command | Result |
| --- | --- | --- |
| `final-coverage.log`, `final-coverage.rds`, `final-coverage-summary.json` | `./run.sh Rscript final-coverage.R` | Tests-only line coverage 91.8730109446557%, or 11,836/12,883 executable lines. Installed instrumented test suite: FAIL 0, WARN 0, SKIP 8, PASS 5504. R 4.6.1, covr 3.6.5, real RBioFormats 1.12.0. |
| `final-coverage.html` | `covr::report(..., browse = FALSE)` | Standalone HTML report written (7,031,921 bytes); HTML structure checked. |
| `final-coverage-by-file.csv` | `coverage-report.R`: supported line tally aggregated by filename | Per-file executable/covered line counts and percentages. |
| `final-coverage-input-sha256.rds` | Hash every R/test file before the run; compare inventory and bytes afterward | `source_unchanged: true`; includes additions/removals as well as changed bytes. |
| `final-coverage-library/hyperannotatR/hyperannotatR-tests/testthat.Rout` | Instrumented installed `test_check("hyperannotatR")` | Full test transcript and all eight named skip events. |
| `final-node-tests.log` | From W: `node --test tests/audit/widget.test.js tests/audit/keyboard.test.js` | 59 passed, no failures/skips. JavaScript did not change afterward. |

The eight installed-run skips are intentional and named: two browser opt-ins,
a CUVIS measurement requiring a permitted fixture, three private-workbench
integration checks, a development-source-only load test, and the unavailable-
RBioFormats behavior test because RBioFormats is installed. Independent browser,
real loopback HTTP and native OME checks have separate owner evidence. These
results do not qualify a vendor SDK measurement, excluded private data, another
operating system, a real partner application or a deployment.

## Intermediate evidence

- `candidate1/`: initial full source suite (5,442 passing expectations; no
  failures/errors/warnings) and initial coverage (91.8380%). The first report
  wrapper used an unsupported `tally_coverage(by = "file")` argument after the
  coverage object was saved; reporting was recovered from the unchanged object
  using the supported line tally. This was an external reporting error.
- `candidate2/`: affected app suite (105 tests, 677 passing expectations) and
  coverage after the app Stage-import repair (91.8564%, 5,457 passing installed
  expectations). The subsequent control companion checks and minimum-dependency
  example/test repairs supersede these candidates.

The intermediate folders explicitly record source drift and are not final
release claims. Full package checks, manual/site build, release metadata and
publication decisions remain in the parent repository handover.
