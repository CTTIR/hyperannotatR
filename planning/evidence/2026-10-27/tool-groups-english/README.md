# Grouped tools and English nomenclature

The annotation palette uses four groups: Navigate, Draw & mark,
Measure & detect, and Edit & reuse. Buttons retain their event IDs and
keyboard bindings while gaining local icons, visible English names,
tooltips and focus/selection styling. Keyboard help is collapsible.
CSS URLs include a content hash so a local update loads the new layout.

The TSCI workspace uses English sentence case for all active layer and
label names. The recorded mapping includes Reflections, Calibration /
Retractor thickness, and Optimal spinal cord view. This is a name-only
migration; the latter remains an optical-quality label independent of
visible injury. Historical checkpoints and exports are not rewritten.

| File | Command or procedure | Result |
|---|---|---|
| tests.log | `NOT_CRAN=true Rscript -e 'testthat::test_local(".", filter="^(app-modules-extra\|app-calibration\|app-drawing-tools)$")'` | 236 assertions pass; no failures, warnings or skips |
| browser.log | Existing `tests/browser/drawing-tools.R` journey, clicking nested button icons; screenshots at 1500 and 1100 pixels, light/dark | Point sizes, all fixed round areas and reflection preview/discard/accept pass |
| calibration-browser.log | `tests/browser/calibration.R`, English reference names | Two-click drawing, mean/SD, undo/redo and fresh app resume pass |
| tools-light.png, tools-dark.png, tools-narrow.png | Synthetic-image browser captures | Visually reviewed icons, labels, active state, contrast and wrapping |
| migration-qa.log | `migrate.R <workspace> $TMPDIR/tool-groups/qa-final <report>` | All 95 images pass; all 147 ROIs match exactly after reversing label text changes |
| migrate.R, names.R | Name migration and explicit geometry/provenance verification | Layer styles, calibration statistics, physical scale and completion states preserved |
| install.log | `R CMD INSTALL --library=<scratch-library> <prepared-source>` | Installed successfully |
| installed-verification.log | Fresh installed-package readback | All English names and five calibration lines retained |
| deployment.json | Backup, package replacement, name migration and fresh verification | 147 ROIs, 28 complete images; original project generations unchanged |

The restarted live endpoint returned HTTP 200 and served the grouped tool
labels. No raw images or cubes were changed. Log whitespace is normalized
and machine paths are redacted. The original logs remain in the scratch
directory. Existing user changes to repository guidance and build-ignore
files are outside this change.
