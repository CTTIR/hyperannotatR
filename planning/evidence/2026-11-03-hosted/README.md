# Hosted portability follow-up — 3 November 2026

Baseline: `33094e4e2fd1`, hosted R check `41604959935`. Preserve the original
working copy and its local changes. The Windows release job failed seven
assertions/errors and warned eleven times; the informational R 4.3 row failed
eight tests. These are observed hosted failures, not inferred platform risks.

## Repairs and acceptance criteria

1. Replace Windows' unavailable `Sys.readlink()` classification with `fs` for
   handoff and export descendants, existing destinations and dangling links.
   Do not permit aliases or traverse linked handoff directories.
2. Inspect canonical ENVI header/payload metadata and source signatures so a
   valid link is not mistaken for a zero-byte payload. Preserve the selected
   companion and retarget checks. Replace only the affected test link lifecycle
   with `fs` operations: base Windows unlink failed to remove reparse points,
   leaving the intended valid recovery fixtures still pointing outside root.
3. Call the exported OME accessor by its local name for RBioFormats 1.2.0's
   introspection convention. Keep all series, axes and calibration checks.
   Retain independent hash checks on older R using OpenSSL, distinct from the
   package's digest fallback.
4. Require affected and complete tests, a source package check, unchanged
   fixture pins, independent code review and exact-head Windows CI before
   claiming native Windows qualification. No workflow or R minimum is relaxed.

The change introduces one mandatory dependency, fs, for portable link
classification. It does not change schemas, annotation IDs, stored paths,
scientific pixel values or supported in-root image links. It does not provide
an operating-system sandbox or protection against concurrent hostile changes
to path components.

## Evidence recorded so far

Logs are retained in the audit's local `hosted-followup/hyperannotatR` folder;
machine paths are omitted here. Failed intermediate harness runs are retained.

| File | Command or method | Result |
| --- | --- | --- |
| portable-links-baseline-canonical.log | Actual links with Windows readlink/zero-size metadata simulated | Five failures before the repair; initial noncanonical test-path run retained separately. |
| ome-accessor-baseline.log | Actual OME image with a name-sensitive dependency accessor | Qualified-call failure reproduced before the repair. |
| portable-final-smoke.log | Focused link, metadata and independent digest regressions | 17 assertions pass; one Windows-only junction test awaits that host. |
| old-rbio-readers-final.log | Install official RBioFormats 1.2.0 in an isolated library; run reader correctness, windowing and accessor tests | 306 assertions pass, zero failures/warnings/skips. Bio-Formats 6.12.0 was downloaded by that dependency's installer. |
| independent-app-review.json | Independent source and test review | No material finding; native Windows execution remains a separate gate. |

An intermediate SHA oracle retained OpenSSL's hash class; its conversion to a
plain character result was corrected. An intermediate dependency mock delegated
under the wrong function name; that harness was corrected and the actual older
dependency rerun successfully. Neither intermediate failure is counted as a
passing test.

Authoritative references: the [R readlink documentation](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.readlink.html),
[fs link classification](https://fs.r-lib.org/reference/is_file.html), and the
[official RBioFormats 1.2.0 source](https://bioconductor.org/packages/3.18/bioc/src/contrib/RBioFormats_1.2.0.tar.gz).

## Final local qualification

The complete direct suite passes 5,523 assertions with zero failures or warnings.
Eight named skips cover the Windows junction case, unrequested browser lanes,
unavailable permitted workbench/Cubert data, and the absent-optional-reader case
when RBioFormats is installed. No source data or fixture pins changed.

The source archive passes `R CMD check --as-cran`: zero errors, zero warnings,
one incoming new-submission NOTE. Its installed tests pass 5,479 assertions with
14 named CRAN/platform/optional skips; examples, donttest examples, vignettes,
PDF and HTML manuals pass. SHA-256:
`00f66fe2a0d1bb0d8a5bd99b0289b98a24741364cbc1f34bb4487544c0993ab3`.
All 552 comparable source payloads match; DESCRIPTION differences are standard
build reflow and derived author/packaging fields. No Git metadata or diagnostic
Rplots file is packaged.

Actionlint and `git diff --check` pass. House lint remains report-only: 84 at the
frozen baseline, 86 after these changes; the two additions are deliberate
synthetic error fixtures. No check was disabled or weakened. An independent
review found no material defect in the changed source and tests. These local
results do not substitute for the pending exact-head Windows run; the browser
lane was not rerun because no browser code changed.

The first-use path remains `pak::pak("CTTIR/hyperannotatR")`, followed by
`hyperannotatR::at_annotate(hyperannotatR::at_example_session())`; optional native
readers retain their documented prerequisites. No release or submission was
performed. Next publication step is the authorized normal main push and hosted
matrix verification.

## Windows fixture correction after hosted execution

The published `ec10690321bca5eb416b32f87a9c1e74c648bdd3` passed the five
Linux/macOS R-check rows, including oldrel-3, but the native Windows row failed
with 28 failures and 17 warnings. The new fixture helper had used
`fs::link_create()` for every target. Its Windows implementation creates a
directory junction even when the target is a file, producing invalid-directory
errors instead of exercising a genuine file symlink. The exact hosted log is
retained as `hosted-failed.log` in the local follow-up evidence.

The helper now uses base `file.symlink()` for Windows file and dangling-file
targets, retains directory junctions for directory targets, and continues to
remove links explicitly before recursive fixture cleanup. Creation failure is
an error, not a skipped security assertion. Seven additional assertions verify
link classification, readable file bytes, resolved identity, dangling behavior
and directory behavior. Existing containment, retargeting and error-code
expectations are unchanged. No runtime source or fixture source data changed.

This behavior was checked against the [fs implementation](https://github.com/r-lib/fs/blob/v1.6.6/src/link.cc)
and [R canonical-path documentation](https://stat.ethz.ch/R-manual/R-devel/library/base/html/normalizePath.html).
An independent review of the two test-file changes found no weakened guard.
Native Windows qualification remains pending the corrected exact-head run.

All four suites using the shared link helper pass locally after correction:
128 assertions, zero failures or warnings, and one genuine Windows-only junction
skip on macOS. These are the app path boundaries, control import boundaries,
portable link contracts and source-retargeting suites. Runtime bytes are unchanged
from the archive already checked locally; the next hosted run checks the
corrected test package on Windows. An initial local invocation used unavailable
`devtools`; the actual successful command used `testthat::test_local()`.

## Dangling-link oracle after the corrected native run

At `7c16da7e96040b6f7cdf63362bca8b6c1252cb66`, native Windows passed 5,473
assertions with zero warnings and 18 existing platform/optional skips. The sole
failure was the added fixture assertion expecting `file.exists(missing_link)`
to be false. The actual Windows result was true. The genuine file-link,
containment, retargeting, and export-refusal checks passed.

The [official R file-manipulation documentation](https://stat.ethz.ch/R-manual/R-devel/library/base/html/files.html)
explicitly states that `file.exists()` is unreliable for broken symbolic links
on Windows. The fixture now checks the known ordinary target is absent, retains
link and non-directory classification, and requires reading through the dangling
link to fail with its connection warning/error. This strengthens the observable
fixture contract without treating OS-specific link existence as target
readability. No runtime or production-refusal assertion changed. Exact native
confirmation of this test-only correction remains pending its next hosted run.

The failed Windows log is preserved as `hosted-windows-fixture.log` in the local
follow-up evidence. Previous source-archive validation still covers identical
runtime files; it is not presented as a fresh check of this final test package.

The four affected app/control/link/source-selection suites pass 130 assertions
locally, with zero failures or warnings and one Windows-only junction skip.
The first three suites passed before the receipt exporter encountered a list
column; their complete RDS result was retained and combined with the separately
run source-selection suite. No failed test is counted as passing. The exact
native Windows run is still required for this final oracle.
