# Reader audit and repair evidence — 2 November 2026

Scope: public hyperannotatR baseline `23cc5f94bef632e82ee14d56955d946b693de827`,
using only small synthetic fixtures and bundled public fixtures. No private
annotation workspace or scientific source dataset was read. Source changes are
in the isolated worktree; the frozen baseline source was not modified.

## Confirmed defects repaired

| Finding | Severity and user impact | Evidence and repair |
| --- | --- | --- |
| TIVITA profile dependencies were omitted | High: changing only sidecar endian changed all 12 values after close/save/reload; first value 111 became 7.9731080023153442e-41, while inspection reported available and saved metadata still said big endian. | `probe.R`, `probe-results.json`; `R/backend-tivita.R` now records the selected profile file, checks discovery precedence and newly introduced sidecars/ENVI headers, and refuses old profiles whose provenance is unverified. `R/persistence.R` compares effective profile digest and value unit on reopen. |
| ENVI companion discovery could select another file | High: adding an eight-byte higher-priority sibling changed reopened pixels from [11,22] to [99,88], despite the recorded payload remaining unchanged. | `selection-probe.R`, `selection-probe.json`; source inspection now compares canonical selected header/payload paths against recorded semantic roles. Header precedence, symlink retargets, and TIVITA ENVI exports are covered. Both sides are normalized for old Windows path separators. |
| Invalid scientific inputs were silently coerced | Medium: band 1.9 selected band 1; a factor white reference labelled 1000 became numeric code 1 and produced reflectance 500 instead of the numeric-reference result 0.5. Infinite white reference produced a seemingly valid zero. | `probe.R`, `probe-results.json`; `R/hsi-meta.R` validates real whole band indices and finite numeric reference vectors before conversion, with classified errors. Missing calibration retains its existing error; zero white-minus-dark still yields NA. Nonfinite wavelength bounds are refused. |
| Closed images lost caller cache/accounting identity | Medium: two identical requests doubled binary reads/decoded bytes, while `at_read_stats()` stayed at zero. | `lifecycle-probe.R`, `lifecycle-results.json`; cached tiles are now found under caller identity, source validation runs before cache lookup, and reopening happens only on a miss. Closing/loading still mint fresh identities. Exact-count regression expects one 16-byte payload read/32 decoded bytes for a repeated 2x2 single-band request. |

New regression files in the worktree:

- `test-tivita-source-validation.R`: sidecar mutation/removal/addition/precedence,
  unchanged and explicit profile compatibility, old descriptor relinking,
  invalid scientific arguments and valid arithmetic.
- `test-reader-source-selection.R`: ENVI payload/header precedence, symlink
  retargets, TIVITA exports, and new ENVI headers beside a bare SpecCube.
- `test-reader-lifecycle.R`: exact samples and byte counts, cache hits,
  independently closed identities, and changed-source rejection before cache.

Stored schema versions, legacy wire identifiers and pinned fixtures are
unchanged. Older sidecar-based projects without the profile dependency still
load their annotation structure, but pixel access requires deliberate
`at_relink_source()` revalidation. Explicit profiles continue to ignore
incidental sidecars. File signatures remain size/mtime checks, not hashes.

## Verification

All commands below run from the external repository evidence directory using
`./run.sh`, which supplies the isolated R library. `W` means the isolated
worktree; baseline means the immutable `baseline-source` snapshot.

| File | Command | Result |
| --- | --- | --- |
| `regressions-baseline-final.log` | `./run.sh Rscript readers/run-regressions.R baseline-source readers/test-reader-provenance.R` | Expected failure: 48 failing expectations against baseline. |
| `selection-baseline-final.log` | `./run.sh Rscript readers/run-regressions.R baseline-source readers/test-reader-source-selection.R` | Expected failure: 16 failing expectations against baseline. |
| `lifecycle-baseline.log` | `./run.sh Rscript readers/run-regressions.R baseline-source readers/test-reader-lifecycle.R` | Expected failure: 8 failing expectations against baseline. |
| `focused-tests-freeze.log`, `focused-tests-freeze.rds` | `testthat::test_local(W, filter="^(tivita-source-validation\|reader-source-selection\|reader-lifecycle\|backend-tivita-profile\|hsi-meta\|persistence-source\|persistence-contract\|persistence-legacy\|reader-provenance\|backend\|identity)$")` | 66 tests, 539 passing expectations; zero failures, errors, warnings or skips. Includes all 112 expectations in the 12 new tests. |
| Working-tree diff | `git diff --check` | Passed. |

Integrity and app reviewers independently inspected the reader changes and
reported no remaining material issue. Whole-package, installed-build, browser,
documentation, OME qualification and release checks belong to the parent lane;
the focused results here do not claim those outcomes.

## Independent review of integrity repairs

Review of partner commit staging/rollback and failed control startup cleanup
found those repairs coherent. An independent small-file probe then identified
that the in-process replay registry still bypassed destination and revision
validation (`integrity-review.log`). This was reported and repaired by the
integrity owner. Re-running the same probe confirms that stale same-process
replays and destination changes now fail (`integrity-review-fixed.log`).

Review of the mask grid guard found the allocation check correctly precedes
integer coercion and rasterisation, preserving ordinary fractional extents.
A missing required label in its new dimension test was reported to its owner
for correction before relying on that regression evidence. Per-grid preflight
does not limit aggregate `at_mask_stack()` memory across multiple layers.

## Explicitly deferred limitations

- Ordinary TIFF remains eager. An 8x8 fixture decodes 512 bytes with
  `max_read_bytes=8`; current documentation scopes this budget to window/NPY
  decoding rather than all TIFF reads. No TIFF predecoder/parser was added.
- Array byte budgets do not cap process RSS, encoded input buffers, native
  decoder memory or geometry-library allocations. No huge allocation was
  attempted to measure these limits.
- Vendor SDK, Windows/Linux native behavior, minimum supported R and real
  scientific/partner workflows require separate environment-specific evidence.

No further broad reader audit or source edits are planned in this lane.
