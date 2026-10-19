# Audit of annotatR 0.2.0, 2026-10-18

Revision: `main` at `6540ec9` (package version 0.2.0); the fixes described here were rebased onto `288c1c5` and published as `77657d6` (release 0.3.0) on top of the rename to hyperannotatR (`bbfd072`). Platform: macOS 27.0.1 (arm64), R 4.6.1 (Homebrew), magick 2.9.1, sf with GDAL 3.13, shiny 1.14.0, headless Chrome for Testing 156 through chromote and Playwright 1.64.1. Commands and results are in the [evidence README](README.md).

## Method

1. Baseline at `6540ec9`: full test suite, CTTIR house linters, and the app driven in a real headless browser with three distinct images (an 8-bit RGB PNG, a 4-band 16-bit pyramidal TIFF and a 40-band ENVI cube) so that wrong-image defects are visible.
2. Seven independent static reviews, one per area (core model and geometry; masks, extraction and plots; readers and interchange; partner interop and training; control service; Shiny app and canvas widget; packaging, documentation and tests), each checking the status of A01–A25 in its files. The app review's W series covers both the app and the widget; the table lists its widget items in a separate row.
3. The unmerged `improve/roadmap` work (T00–T14, A01–A33) was ported first; the remaining findings of this audit were then fixed area by area, each with a regression test that fails before the fix.
4. Integration: documentation regenerated with roxygen2 8.0.0 (the version the package pins), full suite, node tests, browser lanes, clean-export `R CMD check --as-cran`, house lint, and a second real-browser walkthrough compared against the baseline screenshots.

## Findings not covered by A01–A33

Severity: P1 wrong result, lost work or security impact in a common workflow; P2 narrower; P3 quality or documentation. All listed findings are fixed with a regression test unless marked open.

### Found by visual inspection

| ID | Sev. | Finding | Status |
|---|---|---|---|
| V01 | P1 | Every PNG/JPEG read through magick returned scrambled pixels (magick 2.9 `as.integer()` already transposes the bitmap; the reader transposed again). The canvas showed a grey 3×3 tile pattern instead of the image, and every value taken from such an image (plots, extraction, spectra, training tiles) was wrong. The test suite passed because no test compared decoded pixels with an independent decoder. | Fixed; tests against `png::readPNG()` on non-square 1–4 channel images |
| V02 | P2 | README figure showed the scrambled image. | Fixed (re-knitted) |
| V03 | P2 | Mask preview plots were cropped to the annotated region and drawn in downsampled pixel units labelled as image pixels. | Fixed; plots frame the whole grid in image coordinates |
| V04 | P2 | Natural-colour display stretched 8-bit images (per channel on the canvas, jointly in plots), shifting the colours of H&E-like images. | Fixed; 8-bit images show stored values by default |
| V05 | P2 | Letter shortcuts were dead after clicking any toolbar button (a focused button counted as a form control). | Fixed (node test) |
| V06 | P2 | The canvas-ready handler sent `clear_overlay` on every ready render, removing overlays set by proxies. | Fixed (Playwright widget runner) |
| V07 | P3 | The checkpoint line was clipped in the toolbar; error notices showed raw cli markup and console-only hints; the save time was lost after a reload; the narrow layout clipped the queue and the add-layer inputs. | Fixed |
| V08 | P3 | A trusted `dblclick` was ignored, so polygons could not be finished with slow system double-click settings. | Fixed (node test with a controlled clock) |
| V09 | P3 | Two save indicators; a dashboard axis below zero with no ROIs; no hints on an empty Summary page; the cube status read 0 bytes. | Fixed |
| V10 | P3 | Clicking a canvas that was partly scrolled out of view focused it with the browser's default scrolling, so the page moved under the pointer (by up to the hidden part of the canvas) and the next polygon vertices landed off target. Found in the pre-push screenshot walkthrough. | Fixed (`focus({preventScroll: true})`; node test and an app-journey browser assertion that fail before the fix) |

### Static review

| Area | IDs | Summary | Status |
|---|---|---|---|
| Core model | C1–C18 | Reopening stripped images (A01), unique ROI ids across layers and restarts (A07), empty and lower-dimensional set-operation results, pyramid ratios and physical area, mixed-level set operations (A16), validation gaps, derived-ROI attributes, `at_rois()` scaling | Fixed (roadmap T01/T03/T05 plus audit fixes) |
| Masks and plots | M1–M21 | Rectangle fast path (A05), cache identity (A09), export stems (A08), per-ROI pyramid (A21), path containment (A22), bitfield statistics (A20) and codes, background collisions (A17), RDS legends (A19), connectivity (A14), point rule (A15), plot alignment (A18), mixed-geometry overlays, agreement by label, finite-sample policy, tiff-less fallbacks, colour balance, y orientation | Fixed |
| Readers | I1–I18 | Coordinate levels in GeoJSON/CSV/QuPath (A06), NPY payloads and integer ranges (A13, A28), multi-page TIFFs, GeoJSON shapes, Cubert modes, CSV fidelity, dtype, subprocess errors, QuPath fidelity, image identity, band calibration, ENVI data type | Fixed; I8 (OME orientation) fixed by the roadmap's A27 reader but not verified here (RBioFormats unavailable); I14 (TIVITA header semantics) open, needs a vendor specification |
| Interop and training | X1–X20 | Minted ids staged as updates, manifest paths outside the inventory, export levels, entry joins, locked layers, duplicate ids, unserialisable attributes, manifest size limit, dataset replacement, token RNG on Windows, canonical JSON, directory symlinks, dataset checks, split names, mask ids, non-GeoJSON input, tile dtype, version-check order, schema validator gaps | Fixed; X11 fractional-number canonical form documented as differing from qupflowR's integer-only rule |
| Control service | S1–S17 | App–hub synchronisation across entries (S1–S6), expiry, proxies, commit atomicity, unsaved session loads, body handling, bounded records, path redaction, preview budget, output containment, token file creation | Fixed |
| App (incl. widget) | W1–W27 | Shift+Enter filing (A02), reload losing work, stale images, observer crashes, history after failed loads (A03), temporary output folders, locked layers, rejected drawings, ENVI pairs, folder loads, saved state, server paths, keyboard handling, accessibility labels, edit no-ops, text | Fixed; W17 (server paths) mitigated by `options(annotatR.app_root)` and documented as local use only |
| Widget items of the app review | W3, W10, W11, W18–W20, W24, W26 | Stale or missing images, ghost shapes, unfinished polygons, per-instance routing (A25), label colours, pointer/touch/DPR, edit clicks, documentation | Fixed; a module-proxy addressing bug (overlays and selection never reached the app canvas) found and fixed during the port |
| Packaging | D1–D27 | App logo build-ignored, digest needed at runtime, example and test guards, `graphics` use, Suggests versions, stale `_problems/`, hard-coded version test, metadata, WORDLIST, memory claims, keyboard table, vignette inaccuracies, planning-record status | Fixed; D12 (CI coverage floor 0, lint non-blocking) open: shared-workflow policy decision |

### Found during pre-push qualification

The scoping review of the remaining roadmap work found two more P1 defects, registered in [ADDITIONAL-FINDINGS.md](../../ADDITIONAL-FINDINGS.md) and fixed with regression tests before the push: A34, a port regression in which a project loaded in a new R session could not list its ROIs until something else loaded sf, and A35, planar-separate TIFFs decoded as mostly zeros.

## Decisions recorded

- The roadmap work was ported rather than re-implemented (user decision, 2026-10-18); its designs take precedence.
- Display: an 8-bit image's default view shows stored values; deeper or multichannel data and explicit views are stretched. Analysis always uses stored values.
- Errors raised by persistence, export and app save paths are classified (`at_*_error` with a code); bare `cli::cli_abort()` calls elsewhere remain unclassified and are a candidate follow-up sweep.
- `at_fix_geometry(verbose =)` keeps its argument name (house lint prefers `quiet`); renaming is an API change left for a release decision.
- This work is released as 0.3.0 (maintainer decision, 2026-10-18).
- Direction (maintainer decisions, 2026-10-18 and 2026-10-19): the package becomes hyperspectral-first and was renamed to `hyperannotatR` (`bbfd072`), keeping the `at_` prefix and the identifiers stored in files; histology and cell-level annotation move to segmantR.

## Open items

1. Qualify Windows-host persistence, the CUVIS SDK lane and private TIVITA data (T18). OME-TIFF qualification with RBioFormats goes with the histology work to segmantR.
2. T15 windowed reads are partly ported; T16 (bounded previews and streaming exports) and T17 (performance budgets) are not started. Under the hyperspectral-first scope they are re-scoped to large spectral cubes; gigapixel slide windowing leaves with histology.
3. CI gates (coverage floor, blocking lint) are a decision for the shared CTTIR workflows.
4. CRAN incoming: the package name conflicts with Bioconductor `annotatr`.
5. I2/I3 partner profiles stay `planned` until a real qupflowR client is qualified.
