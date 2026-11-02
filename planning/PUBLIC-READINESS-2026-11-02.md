# Public maintenance strategy — 2 November 2026

## Scope and preserved baseline

Make HSI annotation, quantitative extraction, calibrated interpretation, portable
sessions and partner handoffs dependable on real user workflows. Histology/cell
features belong to segmantR. Preserve legacy annotatR wire identifiers, schemas,
fixture hashes, source data, existing author metadata and the original worktree.
Use only bundled and synthetic public data; the active annotation workspace and
all ignored/private data remain outside this audit.

Original main at `3731c2f` includes three unpublished calibration/tool commits; upstream
`147c06e` adds published branding and a historical status record. The isolated
merge `23cc5f9` includes both and preserves pending handover instructions and build
exclusion. Existing pending branding bytes match upstream. The upstream helper's
classified missing-asset condition is retained. Original files and pending work
are hash-inventoried outside the repository. No push, release or submission is
authorised. Historical planning/evidence records will not be rewritten.

## Essential repairs and acceptance criteria

1. Source provenance and quantitative inputs. A synthetic 12-value TIVITA cube
   changes all values on reopen when only a sidecar endian field changes, while
   source inspection reports available and metadata retains the old endian.
   Track every interpretation-bearing source dependency and reject stale data
   consistently across direct reopen and saved-project reload. Exercise changed,
   removed and newly introduced sidecars where applicable. Preserve correct
   unchanged-source readings and declared spectral metadata. Reject fractional
   band indexes and invalid/non-finite/non-numeric conversion references rather
   than silently coercing them into different scientific values.
2. Transactional partner commits. In-memory image data must survive a commit
   and reload just as ordinary project saves do. Treat the saved project and
   receipt as one recoverable transaction: failure to publish either must retain
   previous completed state. Durable idempotent replay must return a project
   consistent with its receipt/revision, or an explicit conflict. Cover actual
   filesystem failures plus successful/retried calls.
3. Annotation and calibration integration. Exercise drawing, selection, wand
   proposal acceptance/rejection, undo/redo, save/resume and exports in a real
   browser. Global assumed reference lengths and per-image overrides must stay
   distinct, survive persistence and never become falsely measured physical
   calibration. Fix confirmed workflow defects while preserving existing
   calibration controls and supported saved projects.
4. Release evidence. Establish a clean reproducible baseline, then run the full
   R suite, Node tests, relevant fresh-process/resource/interop lanes, actual
   browser workflows, existing coverage measurement, complete manual/vignette
   checks, clean install/first use, README regeneration and documentation site.
   Inspect the built package and preserve fixture/source hashes. Record each
   environment-dependent skip or external gate honestly.

For each milestone: add regression coverage that fails against `23cc5f9`, implement
the underlying repair, run focused tests and direct workflows, request a separate
review, then integrate full checks. New dated findings/evidence live under
planning/evidence/2026-11-02, with a File | Command | Result index; raw machine
logs stay in the external audit evidence and published excerpts redact paths.

## Everyday reliability and deferred scope

Investigate reader lifetime/capability mismatches and bounded allocations with
small synthetic fixtures before selecting further work. Use existing error
classes and compatibility helpers. Do not mechanically implement the old
T15–T18 proposal: a new TIFF engine, broad streaming formats, condition/API
renames and speculative cache redesign are longer-term work unless measured
current workflows demonstrate necessity. A meaningful coverage floor may be
set from actual verified evidence; do not lower or suppress useful checks.

The baseline dependency inventory finds RBioFormats absent; this is an
environment limitation to resolve if feasible, separate from package defects.
Vendor SDK qualification, Windows/Linux host behavior, original R 4.1 support,
real partner clients and release/submission approval need distinct evidence.
Synthetic data validation does not certify scientific annotation quality or
establish a physical image scale.

## Confirmed refinements during baseline review

- Failed control-service startup can leave a registered hub and listener after
  an error. Validate the root early and unwind only newly created resources.
- Distinct control hubs collide on the same client idempotency key. Scope
  internal keys by instance without changing the wire contract.
- The Data tab accepts an allowed directory whose symlinked image resolves
  outside the configured app root. Check each canonical candidate and known
  companions before loading, including directory cycles and valid recovery.
- Closed-image reads change cache/accounting identity, doubling repeat I/O and
  leaving the public read counter at zero. Preserve caller identity and check
  source freshness before cache reuse.

The frozen baseline passed 5,113 assertions without failures/warnings, with nine
skipped test rows and ten named skip events. Node passed 59/59. The initial full as-CRAN
check stopped on missing RBioFormats. An isolated rJava/Bio-Formats installation
resolved this without altering global R configuration; the complete baseline
then passed with no errors or warnings and one new-submission NOTE.
Zenodo's public API returned 404: persistent identifier 21889921 is not registered.
Remove the unregistered DOI from new candidate metadata while retaining author
information and historical records.

## Refinements found in complete release checks

The final independent review extended restricted input checks to staged import
inventories and legends, with baseline-failing tests and actual browser recovery.
A minimal-dependency check then exposed examples and test fixtures that assumed
optional PNG/TIFF readers. Correct those assumptions while retaining substantive
export, detection and migration assertions. Core examples should use the bundled
ENVI cube where that better demonstrates the API without extra dependencies.
The analogous control-service staging and session-loading paths now share
explicit-root preflight checks, verified through the public HTTP client.

Keep normal full checks and a separate minimal-dependency lane. A successful
full installation must not conceal broken examples for users without optional
readers. Revised candidates require affected regressions, complete package checks
and a final coverage measurement after runtime sources are frozen.

Documentation review also found a duplicated article logo and a source-only
handover link rendered as a missing site page. Scope the logo fix to the site
and retain standalone vignette branding. Standard R PDF generation clips a few
long links; preserve that output and supply a separately identified readable
PDF with ordinary TeX line-breaking adjustments, unchanged content and verified
page references. These documentation repairs do not alter analytical behavior.

## Completion

All selected local acceptance criteria passed on the frozen third candidate:
full and minimal as-CRAN checks, installed workflows, source instrumentation,
actual browser/HTTP flows, site navigation and a readable source-bound manual.
The final report and machine-readable results are in
`planning/evidence/2026-11-02/`. Remaining platform/vendor/publication gates and
explicit resource/concurrency limits are deferred there, with no remote release
or production claim. No further cosmetic iteration is part of this milestone.
