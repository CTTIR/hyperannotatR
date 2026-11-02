# AGENTS.md: hyperannotatR

Instructions for coding agents working in this repository. For the current
state of the work and what to do next, read
`planning/HANDOVER.md` first (in the source checkout).

## What this package is

hyperannotatR (renamed from annotatR in 0.3.0) is an R package for multi-layer
region-of-interest (ROI) annotation of hyperspectral imaging (HSI) data:
spectral cubes (ENVI, TIVITA, Cubert, NPY), band views, spectral extraction
and their display rasters. ROIs are validated `sf` geometries in image pixel
coordinates with explicit pyramid-level transforms. They rasterise to binary,
labelled, multiclass or bitfield masks. A Shiny batch annotation app with a
canvas htmlwidget, a versioned partner contract (handoff directories, training
datasets) and an optional local control service complete it.

Scope boundary: histology and cell-level annotation (microscopy cell or nucleus
annotation, segmentation, correction, training, review) belongs to the sibling
package **segmantR**, which carries its own copy of the ROI, mask and canvas
code (`sg_roi_*`, `sg_canvas`). Do not add histology-specific features here.
The QuPath bridge **qupflowR** names hyperannotatR as its annotation partner
through the `annotatr-control-v1` contract.

## Layout

- `R/`: package code. Exported functions use the `at_` prefix and S3 classes
  the `annot_` prefix (`annot_roi`, `annot_layer`, `annot_project`,
  `annot_image`, `annot_mask`, `annot_session`). Areas:
  - classes: `class-*.R`, `hyperannotatR-classes.R`;
  - geometry: `geometry.R`;
  - masks: `mask*.R`, `agree.R`;
  - image backends: `backend*.R`, `io-window.R`, `io-binary.R`,
    `io-tiff-process.R`, `hsi-meta.R`;
  - interchange: `io-geojson.R`, `io-qupath.R`, `io-csv.R`, `io-npy.R`;
  - persistence: `persistence.R`, `io-project.R`, `export-policy.R`;
  - partner contracts: `interop-*.R`, `training.R`, `schema-validate.R`;
  - control service: `control-*.R`;
  - app: `app-*.R`, `widget-canvas.R`.
- `inst/htmlwidgets/atcanvas.js`: the canvas widget.
  `inst/shiny/hyperannotatR/www/`: app assets (`keys.js`, `custom.css`, logo).
  `inst/schema/`: JSON schemas of the partner contracts.
  `inst/extdata/`: example images.
- `tests/testthat/`: unit and regression tests (testthat edition 3).
  - `helper-fresh-process.R` (`audit_fresh()`) runs code in a new R process,
    loading the installed build under `R CMD check` and covr.
  - `helper-tiff-writer.R` writes TIFF layouts that `tiff::writeTIFF()` cannot.
  - `fixtures/`: byte-pinned test data.
- `tests/audit/`: fast node tests of the canvas and keyboard JavaScript.
- `tests/browser/`: real-browser Playwright runners and their R fixtures
  (see `tests/browser/README.md`).
- `tests/qualification/`: manual qualification scripts (Linux memory, Windows
  host, QuPath round trip, installed-process checks). They are not run by
  `R CMD check`.
- `planning/`: roadmap, finding registers and dated evidence. Build-ignored.
- `data-raw/`: generators for example data and fixtures.

## Commands

Run from the package root. R 4.6.1 is the tested version; DESCRIPTION claims
`R (>= 4.1.0)`, which is unverified.

```sh
# Full test suite (about 5 minutes; 832 tests, 9 expected skips without optional software)
NOT_CRAN=true Rscript -e 'testthat::test_local(".")'

# One file
NOT_CRAN=true Rscript -e 'pkgload::load_all(); testthat::test_file("tests/testthat/test-mask.R")'

# Canvas and keyboard JavaScript
node --test tests/audit/widget.test.js tests/audit/keyboard.test.js

# Real-browser lane (shinytest2 + chromote); needs a Chromium-based browser
NOT_CRAN=true ANNOTATR_BROWSER_TESTS=true CHROMOTE_CHROME=/path/to/chrome \
  Rscript -e 'pkgload::load_all(); testthat::test_file("tests/testthat/test-app-browser.R")'

# Playwright runners: start the R fixture, then the node runner (see tests/browser/README.md)
Rscript tests/browser/app-journey.R &   # port 5819; ANNOTATR_BROWSER_PORT overrides
PLAYWRIGHT_MODULE=/path/to/node_modules/playwright CHROMIUM_PATH=/path/to/chrome \
  node tests/browser/app-journey.cjs

# Documentation: roxygen2 must be exactly 8.0.0 (Config/roxygen2/version)
Rscript -e 'roxygen2::roxygenise()'

# R CMD check from a clean export (R CMD build copies ignored local data otherwise)
git archive HEAD | tar -x -C /tmp/hyperannotatR-export
R CMD build --no-manual /tmp/hyperannotatR-export
_R_CHECK_FORCE_SUGGESTS_=false R CMD check --as-cran --no-manual hyperannotatR_*.tar.gz

# CTTIR house linters (config shared in the sibling CTTIR/.github checkout)
Rscript -e 'source("../.github/config/lint-cttir.R"); print(lintr::lint_package(linters = cttir_linters()))'
```

Expected results at 72e2b7d:
- `R CMD check --as-cran` gives `Status: 1 NOTE`, *New submission* only.
- The house lint reports 1 finding in package code (`at_fix_geometry(verbose =)`,
  an open decision) and 57 in tests, examples and vignettes.

`README.md` is generated from `README.Rmd`. Install the package into a scratch
library, then render with
`rmarkdown::render("README.Rmd", output_format = rmarkdown::github_document(html_preview = FALSE))`.
Plots use `ragg` when installed so that colours are exact.

System requirements:
- GDAL, GEOS, PROJ and udunits (for `sf` and `stars`);
- ImageMagick (`magick`, PNG/JPEG);
- libtiff (`tiff`).

Optional software:
- `terra`, `RBioFormats` with Java (OME-TIFF);
- the Cubert CUVIS SDK (`cuvis.r`);
- a Chromium build, node and Playwright for the browser lanes.

Tests whose prerequisites are missing skip with a named reason.

## Invariants: do not change

- **Stored identifiers keep their pre-rename spelling.** Files written by this
  package and by annotatR carry them, and the partners and segmantR read them:
  - `annotatR_version`;
  - the coordinate schema `annotatR-pixel-level-v1`;
  - the QuPath metadata keys `annotatR_roi_id`, `annotatR_coordinate_schema`
    and `annotatR_coordinate_level`, plus the lower-case `annotatr_*` keys;
  - the QuPath object-id seed `"annotatR:roi:"` in `.roi_uuid()`;
  - all lower-case contract ids (`annotatr-handoff-v1`, `annotatr-control-v1`,
    `annotatr-hsi-v1`, ...).

  A blanket rename once broke these. Tests in `test-qupath-native.R` and
  `test-io-qupath-real.R` now guard them.
- **Options use the `hyperannotatR.*` prefix.** The old `annotatR.*` names are
  not read. Test environment variables keep the `ANNOTATR_*` prefix.
- **Byte-pinned fixtures** (`MD5SUMS`, `SHA256SUMS`, `sha256.json`, `*.sha256`
  under `tests/testthat/fixtures` and `tests/fixtures`) change only through
  their generators, with every pin updated. `.gitattributes` marks fixtures
  `-text` so that Windows checkouts keep their bytes.
- **`planning/evidence/<date>/` is a historical record.** Never edit existing
  logs. New runs go into a new dated folder with a README table
  (File | Command | Result). Redact machine paths (`<check-dir>`, `$TMPDIR`).
- **Wire formats and contracts are versioned.** Changing a schema under
  `inst/schema` means a new contract version and matching changes in qupflowR.

## Conventions

- **Errors** are classified conditions: use `.at_abort()` or `.at_fail()`
  with a class and a `code`, giving `at_<class>_error`. Tests assert `err$code`.
- **Regression tests** must fail before the fix. Prove it by running them
  against the unfixed code. Behaviour that only shows on an installed build,
  such as namespace loading, needs a fresh-process test (`audit_fresh()`).
- **Paths in tests** are compared in canonical form
  (`normalizePath(x, winslash = "/")`). Windows CI runs the suite.
- **User-visible changes** go under the top section of `NEWS.md`.
  - Finding ids: `A01`–`A35` are in `planning/ADDITIONAL-FINDINGS.md`;
    `V`/`C`/`M`/`I`/`X`/`S`/`W`/`D` are in
    `planning/evidence/2026-10-18/audit.md`.
  - Register new findings there with severity and evidence.
- **Style:** house lint, 80-column prose and roxygen markdown. Match the
  surrounding code. Ported roadmap tests keep their compact style.
- **Do not edit the README "Use of LLM tools" section.** The maintainer
  writes it.
- **Pushing is a maintainer decision.** Commit locally and ask. The maintainer
  pushes to `main` directly, with no pull requests, and CI runs on push. The
  shared workflows live in CTTIR/.github; do not add steps to the callers in
  `.github/workflows/`.
