# Handover: hyperannotatR status on 2026-10-21

Read [AGENTS.md](../AGENTS.md) for repository rules, commands and invariants.
This file records where the work stands and what comes next.

## Snapshot

| Item | State |
|---|---|
| Branch | `main` at `72e2b7d`, pushed |
| History since 0.2.0 | `bbfd072` rename to hyperannotatR (maintainer), then `77657d6` release 0.3.0, then `21f7b83` planning record, then `72e2b7d` Windows-portable test paths |
| Version | 0.3.0 in DESCRIPTION, NEWS, CITATION.cff and .zenodo.json. No git tag or GitHub release yet |
| Local `R CMD check --as-cran` | `Status: 1 NOTE` (*New submission*); see [evidence 2026-10-19](evidence/2026-10-19/README.md) |
| Tests | 832 tests and 4981 expectations, 0 failures and 9 named skips; node 49/49; shinytest2 and Playwright lanes pass |

What 0.3.0 contains:
- The release notes are in `NEWS.md`.
- The port of roadmap work packages T00–T14 is recorded in
  [IMPLEMENTATION.md](IMPLEMENTATION.md).
- The audit of 0.2.0 is in
  [evidence/2026-10-18/audit.md](evidence/2026-10-18/audit.md). It includes
  real-browser and visual inspection; its findings are V01–V10 plus the
  static-review series.
- Findings A26–A35 are in [ADDITIONAL-FINDINGS.md](ADDITIONAL-FINDINGS.md).
  A34 (sf namespace import) and A35 (planar-separate TIFF) were found and
  fixed after the port.
- How the rename was integrated is in
  [evidence/2026-10-19](evidence/2026-10-19/README.md).

## CI (last seen 2026-10-20, commit `72e2b7d`)

| Workflow / job | State | Note |
|---|---|---|
| R-CMD-check ubuntu release, oldrel-1, devel | pass | |
| R-CMD-check windows-latest | pass | Failed on `21f7b83` because of `/`-joined path assertions in three tests; fixed in `72e2b7d` |
| R-CMD-check macOS-latest | cancelled | Passed on `21f7b83`; the reason was not retrievable. Re-run it |
| R-CMD-check ubuntu oldrel-3 (R 4.3) | fail | Never reaches the check: the Bioconductor 3.18 repositories are unavailable in the shared workflow (CTTIR/.github). Not a code problem |
| test-coverage | fail | Tests pass and the floor is 0. The Codecov upload fails ("Failed to properly create commit") since the repository rename; Codecov needs `CTTIR/hyperannotatR` set up |
| lint | pass | Non-blocking (`blocking: false`) |
| pkgdown | pass | Release mode: 0.3.0 docs at https://cttir.github.io/hyperannotatR/ |

## Sibling repositories (pushed 2026-10-20)

- **qupflowR `4e94ea4`.** The annotation partner is hyperannotatR (Suggests
  and Remotes). Contract ids are unchanged (`annotatr-control-v1`,
  `qupflowr-annotatr-capabilities`, `annotatr_version`). segmantR is recorded
  as the planned histology partner. CI is green.
- **segmantR `f73dfee`.** The planned HSI partner profile is now
  `partner_hyperannotatR`. The commit also restored annotatR as the author of
  the legacy QuPath dialect and fixtures in transferred docs and tests.
- **segmantR CI has been red since the split commit `d358b3b`**, which predates
  `f73dfee`. All 1,704 tests pass; `R CMD check` stops on two documentation
  issues:
  - **WARNING, duplicated Rd aliases:** `sg_roi.Rd` repeats the topic names
    `sg_roi_frame`, `sg_roi_layer`, `sg_roi_mask`, `sg_roi_project` and
    `sg_roi_summary`. The class names became identical to function names.
  - **NOTE:** several `\examples` lines are longer than 100 characters.
  - **Fix:** drop or rename those aliases on the class page and wrap the
    examples.
  - This belongs to the segmantR split work.
- **website `f705b0e`, `.github` `43fa445`.** Software, project and workflow
  listings and the organisation profile name hyperannotatR (HSI). segmantR is
  listed for cell annotation.
- **Deliberately unchanged:**
  - cttiR: its licence inventory and catalogue test record the bundled
    annotatR 0.2.0 snapshot.
  - ressources: its auto-refreshed repository inventory already lists
    hyperannotatR.

## Open items

### Maintainer actions

1. **Re-run the cancelled macOS job** of `72e2b7d`.
2. **Codecov:** connect the renamed repository, or update the token.
3. **README "Use of LLM tools":** the maintainer will write this section. It
   names only Chat AI (KISSKI) and a self-hosted Mistral. Most of the 0.3.0
   work was produced with an AI coding agent (Claude Code), and the planning
   evidence records the agent workflow.
4. **Release:**
   - tag `v0.3.0` and publish a GitHub release (`.zenodo.json` drives Zenodo
     archiving);
   - the DOI `10.5281/zenodo.21889921` in CITATION.cff returns 404 because the
     record is unpublished: publish it or remove it.
5. **Hex sticker:** `man/figures/hyperannotatR-hex.png` still shows the
   "annotatR" wordmark. It is no longer referenced (vignettes use
   `man/figures/logo.png`). Regenerate it with hexmakR, or delete it.
6. **CRAN:** the name conflict with Bioconductor `annotatr` is resolved by the
   rename. The remaining NOTE is *New submission*. Decide whether to submit.
7. **Shared CI policy (CTTIR/.github):**
   - oldrel-3 Bioconductor handling;
   - blocking lint;
   - a coverage floor (audit item D12).
8. **qupflowR follow-ups** (recorded in its NEWS and schema README):
   - whether its future adapter should also detect a legacy `annotatR`
     install;
   - whether to rename its planned `qp_annotatr_capabilities()`.
9. **Partner plan:** [INTEROP_HSI_PLAN.md](INTEROP_HSI_PLAN.md) does not
   mention segmantR as a planned partner yet (segmantR lists
   `partner_hyperannotatR`).
10. **Local cleanup on the original machine:** the branches
    `backup/pre-rename-d1d6e40` and `integrate-rename` are local only. They
    can be deleted.

### Roadmap work for an agent: T15–T18, re-scoped to HSI

The detailed, reviewed specifications are in
[T15-T18-SCOPE.md](T15-T18-SCOPE.md). They were written before the
hyperspectral-first decision, so their plan sized about 250 focused hours,
mostly for gigapixel TIFF windowing that now belongs to histology (segmantR).
Re-scope as follows:

- **Order:**
  1. T18 gates (low risk, independent).
  2. In parallel, the T15 remainder, then T16, then T17.
- **T15, remaining for HSI.** ENVI and TIVITA (SpecCube) already open
  metadata-only and read exact windows; measured byte costs are in the spec.
  Remaining:
  - capability and lifecycle hygiene:
    - per-image `capabilities_fn`;
    - a protected `close_fn` in `at_close_image()`;
    - look up the tile cache under the caller's identity before
      `.reopen_image()` in `at_tile()`, which currently re-reads the header
      (about 149 bytes) on every tile of a closed image;
    - strict telemetry keys;
  - the inconsistent OME-TIFF registry declaration in `zzz.R`, which says
    eager while the reader windows;
  - a byte-budget preflight before the eager TIFF decoder;
  - a portable fresh-process resource harness (on macOS, report the worker's
    own `maxrss` and disable the JIT to remove noise).

  Defer the GDAL/terra windowed TIFF worker unless HSI data arrive as large
  TIFFs. That is a decision for the maintainer.
- **T16, for large cubes:**
  - bounded decimated previews (lattice reads for ENVI and TIVITA);
  - a preview cache keyed by source generation and display settings;
  - queue and app memory retention (MRU budgets, history pruning);
  - an `at_mask()` size guard.

  Streaming mask export has low priority because HSI masks are small.
- **T17:**
  - a benchmark harness in `tests/qualification/performance/` with synthetic
    ENVI and TIVITA cubes of increasing size (cold and warm runs; wall time,
    peak memory, bytes read);
  - a window-scaling regression test;
  - calibrate [VALIDATION.md](VALIDATION.md) from measurements made on a quiet
    reference machine.
- **T18:**
  - bring the house lint to 0 (`stop()` in test doubles and qualification
    scripts, the example script and vignette guards);
  - the `at_fix_geometry(verbose =)` to `quiet` transition, as decided;
  - then make lint blocking;
  - set a coverage floor of trunc(min(local, CI)), about 89–90 %;
  - run the node tests under testthat;
  - write a release checklist mapped to the VALIDATION gates.
- **Decisions needed** (listed in full in the spec):
  - option defaults;
  - the TIFF engine on Windows;
  - adding Suggests `processx` and `ps`;
  - int32, uint32 and float64 TIFF support;
  - canvas PNG bit depth;
  - `touches = TRUE` streaming;
  - `at_fix_geometry()`;
  - CI policy;
  - the minimum R version (`R (>= 4.1.0)` is unverified);
  - checkpoint retention;
  - the cost of hashing whole source files with SHA-256.

## Environment notes (macOS machine used so far)

- **Installed:** Homebrew R 4.6.1 (arm64) and roxygen2 8.0.0.
  - The R package `websocket` is built against `openssl@3`.
  - chromote's Chrome for Testing headless shell lives under
    `~/Library/Caches/org.R-project.R/R/chromote/chrome/`.
  - Playwright 1.64.1 is installed outside the repository (point
    `PLAYWRIGHT_MODULE` at it).
- **Not available there:**
  - Java and RBioFormats (OME-TIFF tests skip);
  - the CUVIS SDK;
  - private TIVITA data and QuPath;
  - Python `numpy` and `tifffile` (needed by the fixture generators);
  - LaTeX (use `--no-manual`).
- **Network:** access to GitHub was unreliable. Pushes needed retries,
  `http.version=HTTP/1.1` and one commit per push.
