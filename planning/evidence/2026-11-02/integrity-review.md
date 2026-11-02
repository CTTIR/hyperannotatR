# Integrity audit — 2 November 2026

Baseline: isolated merge `23cc5f94bef632e82ee14d56955d946b693de827`.
Only bundled or bounded synthetic data were read. No live/private annotation
workspace, service or data was accessed. Repository edits are confined to the
isolated audit worktree; fixtures and historical evidence remain unchanged.

## Confirmed findings

| Finding | Severity and user impact | Evidence and repair |
| --- | --- | --- |
| Partner commits discard in-memory pixels | High. `at_commit_qupflowr` clears every image handle before saving; a supported hand-built image becomes permanently unavailable after reload, while ordinary `at_save_project` retains its pixels. | Baseline `R/interop-handoff.R:1461–1471`; `probe-commit.R`, `commit-results.json`, first regression in `test-commit-durability.R`. Repaired by using ordinary project persistence preparation without indiscriminate handle removal. |
| Receipt failure leaves a partially committed project | High. An existing receipt-path directory or failure of receipt publication occurs after the project replacement. The original bytes are lost and retry fails with `REVISION_CONFLICT`, despite the call reporting failure. | Baseline `R/interop-handoff.R:1465–1478`; actual directory collision and injected second publication failure. Repaired by `.export_bundle` staging and recoverable publication of the RDS plus receipt. Both previous files are verified byte-identical after simulated failure, and retry succeeds. |
| Durable replay returns incompatible project/receipt | Medium. If the project is edited after a commit, a new R session's replay returns the old receipt revision paired with the newer project. | Baseline `R/interop-handoff.R:1427–1436`; `probe-commit.R` and fresh-process regression. Repaired by a shared replay check for cached and durable receipts: reload the selected project, compare its annotation revision, and reject mismatches with `REVISION_CONFLICT`. Reusing a cached key for another canonical destination now raises `IDEMPOTENCY_CONFLICT`; memory-only replay remains supported. |
| Failed control startup leaves owned resources active | High. A regular file passed as root, or failed lifecycle-manifest publication, errors after registering a hub/token and potentially starting a listener/timer. The caller receives no handle to stop it. | Baseline `R/control-server.R:260–296`; actual regular-file root in `probe-control.R`; focused `test-control-startup.R` covers serving and in-process modes and real listeners with injected manifest rename failure. Repaired with early root validation and an error-path cleanup of only this attempt's hub, token file, registry entries, listener and timer. Unrelated listener/callback and existing files survive. |
| Separate control instances collide on commit keys | Medium. Two independent clients use the same ordinary idempotency key for identical annotation patches on different images. The process-global commit cache returns the first hub's project to the second; session identity validation then refuses the second valid commit with `IDENTITY_MISMATCH`. No project corruption observed. | Baseline `R/control-commands.R:626`; `probe-control-scope.R` uses only public client calls and two synthetic PNGs. `control-scope-results.json` records the failure. Repaired by hashing the control instance id and client key into the internal process-wide commit key. Public wire keys and schema are unchanged; same-instance retries and 128-character client keys work. |

| Full masks bypass allocation limits | High resource-risk limitation confirmed using tiny requests under deliberately low budgets. `at_mask` allocated complete grids without consulting the existing byte limit. | Repaired in `R/mask.R` with positive/finite dimensions, ceiling-preserving integer/index validation, and a pre-rasterisation 32-bytes-per-pixel working-array estimate against `hyperannotatR.max_read_bytes` (default 1 GiB). Tests use sentinels to stop the baseline before any large allocation. |

## Verification evidence

Commands below run from external evidence/integrity unless stated otherwise;
`W` denotes the isolated worktree and `BASE` the frozen baseline-source tree.
`../run.sh` selects isolated audit libraries. No authentication tokens were
printed in these logs.

| File | Command | Result |
| --- | --- | --- |
| `probe-commit.log`, `commit-results.json` | `../run.sh Rscript probe-commit.R` against untouched baseline-loaded source before editing | Reproduced all three commit defects using a 12-value array and a tiny PNG. |
| `probe-control.log`, `control-results.json` | `../run.sh Rscript probe-control.R` before editing | Reproduced orphan running hubs in both modes and an orphan live listener in serving mode. The probe shut down its own leftovers; original root file and preexisting registry/listeners were preserved. The JSON token count was collected after cleanup; baseline regression evidence separately verifies token leakage before cleanup. |
| `baseline-commit-tests.log`, `.rds` | `../run.sh Rscript run-focused.R BASE test-commit-durability.R baseline-commit-tests.rds` | All 5 tests fail unfixed code: 12 failed expectations, 3 errors, 3 expected filesystem warnings. The publication mock matches canonical paths. |
| `baseline-control-tests.log`, `.rds` | `../run.sh Rscript run-focused.R BASE test-control-startup.R baseline-control-tests.rds` | All 4 tests fail unfixed code: 19 failed expectations. Test cleanup shuts down only its new hubs. |
| `fixed-commit-tests.log`, `.rds` | `../run.sh Rscript run-focused.R W test-commit-durability.R fixed-commit-tests.rds` | 5 tests, 32 expectations pass; no warnings. |
| `fixed-control-tests.log`, `.rds` | `../run.sh Rscript run-focused.R W test-control-startup.R fixed-control-tests.rds` | 4 tests, 34 expectations pass; no warnings. |
| `affected-tests.log`, `.rds` | From W: `testthat::test_local(".", filter="^(commit-durability|interop-handoff|control-startup|control-protocol|control-lifecycle|export-contract)$")` | 80 tests, 535 expectations; no failures/errors/warnings. |
| `probe-control-scope.log`, `control-scope-results.json` | `../run.sh Rscript probe-control-scope.R` loading BASE | Two equal patch digests; first commit succeeds, second returns `IDENTITY_MISMATCH`; original image identity survives in both hubs. |
| `baseline-control-scope-tests.log`, `.rds` | `../run.sh Rscript run-focused.R BASE test-control-commit-scope.R baseline-control-scope-tests.rds` | Ordinary equal client keys reproduce `IDENTITY_MISMATCH` for the second hub. |
| `baseline-mask-tests.log`, `.rds` | `../run.sh Rscript run-focused.R BASE test-mask-budget.R baseline-mask-tests.rds` | Budget/index regression tests fail (57 failed expectations, 1 error); exact fractional-mask compatibility test passes. Huge-grid rasterisation is intercepted, so no huge allocation is attempted. |
| `final-affected-tests-first.log` | First combined masks/contracts/control lane | One missing label in a new synthetic test fixture stopped the dimension test before the guard was exercised. Independent review caught it; fixture was corrected, baseline replayed and final lane rerun. Production guard unchanged. |
| `final-affected-tests.log`, `.rds` | From W: `testthat::test_local(".", filter="^(mask.*\|audit-mask\|control-commit-scope\|commit-durability\|interop-handoff\|control-startup\|control-protocol\|control-lifecycle\|export-contract)$")` | 183 tests, 1096 expectations, zero failures/errors/warnings. All 13 added tests pass (140 expectations), including scoped retries, maximum-length wire keys and mask compatibility. |
| `test-counts.txt` | Load each saved result with testthat and aggregate `as.data.frame(result)` | Machine-readable result counts summarized above. |

## Boundaries and remaining considerations

- The existing shared bundle helper stages every file and rolls back ordinary
  publication failures. Multiple filesystem renames are not crash-atomic, and
  concurrent writers to one destination must be serialized by the caller.
  Failed rollback retains the previous files at reported backup paths.
- Normal checkpoint generations use staged immutable projects and manifest
  publication; no new checkpoint correctness defect was confirmed in this review.
  Generation retention/garbage collection remains a maintenance policy question.
- `at_mask` now has the shared per-grid preflight described above. The estimate
  excludes geometry/native-library overhead and is not an RSS guarantee.
  `at_mask_stack` retains multiple layer matrices and their combined stack;
  aggregate multi-layer memory remains outside this narrow repair. Trusted
  callers may raise the existing limit. No large allocation was attempted.
- Training export stages and checks a whole dataset before recoverable directory
  replacement. No new release-blocking training defect was confirmed. Input
  edge cases such as infinite fractions and portable case-folded split aliases
  remain suspected minor validation gaps, not established scientific corruption.
- Authentication gates retain strict loopback/Host/token/origin checks; schemas
  and legacy annotatR wire identifiers were unchanged. Real partner applications,
  non-macOS hosts and production deployment are not certified by this audit.

## Independent review

- Reader reviewer inspected bundle rollback, failed-start cleanup, shared replay
  checks, canonical destination identity and mask-budget placement. Its separate
  replay probe now rejects both same-process stale state and alternative targets.
  No material issue remains in the reviewed changes; stack-memory limitation is
  explicitly deferred above.
- App reviewer independently committed and reloaded a three-band 60-value
  in-memory fixture, retaining all values and assumption metadata. Same-process
  and fresh-process replays succeeded; a subsequent annotation edit caused
  `REVISION_CONFLICT` while project/receipt bytes remained unchanged. Evidence:
  sibling `app/commit-integration-{create,reopen}.log`. Final real-browser
  save/resume/export integration passed in the separate app lane.
- This reviewer inspected the reader provenance/cache and app input-containment
  changes against their callers and discovery functions. No new material issue
  was found. Full-package release checks remain the parent task.
