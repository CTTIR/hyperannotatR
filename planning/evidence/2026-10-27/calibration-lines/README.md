# Repeated calibration reference lengths

The canvas now records a straight LineString from two clicked endpoints.
Layers with `role = "calibration_reference"` default to this tool. Each
label has its own count and level-0 pixel distances. The mean and sample
standard deviation require at least three valid measurements; five are
recommended. The image's physical calibration is unchanged.

The new tests failed before the implementation: the canvas emitted no
line, the summary functions were absent, and copy-forward duplicated the
reference. Final checks cover actual pyramid dimensions, invalid and
copied measurements, independent labels, automatic tools, undo/redo and
checkpoint resume. The browser fixture uses synthetic data exclusively.

| File | Command | Result |
|---|---|---|
| red-r.log | `NOT_CRAN=true Rscript -e 'testthat::test_local(".", filter="^app-calibration$")'` before implementation | 5 expected failures |
| red-node.log | `node --test tests/audit/widget.test.js` before implementation | Two new line tests fail |
| tests.log | `NOT_CRAN=true Rscript -e 'testthat::test_local(".", filter="^(app-calibration\|app-drawing-tools\|app-modules-extra\|app-builder\|app-state\|widget-canvas)$")'` | 413 passing assertions, no failures or warnings; one opt-in browser skip |
| green-node.log | `node --test tests/audit/widget.test.js tests/audit/keyboard.test.js` | 59 passing tests |
| browser.log | `NOT_CRAN=true CHROMOTE_CHROME=<chrome> ANNOTATR_BROWSER_ARTIFACT_DIR=$TMPDIR/calibration-lines/browser Rscript tests/browser/calibration.R` | Trusted mouse clicks, 3/5 threshold, exact distances, mean/SD, undo/redo, fresh app resume and tool restoration pass |
| five-measurements.png | Screenshot from `tests/browser/calibration.R` | Visually reviewed five lines, count, mean and SD |
| install.log | `R CMD INSTALL --library=$TMPDIR/calibration-lines/library $TMPDIR/calibration-lines/source` | Installed successfully |
| compatibility.log | Fresh installed-package verification against all 95 workspace images | Reference role and pixel units retained; arithmetic verified independently |
| deployment.json | Desktop package replacement with verified backup and annotation hashes | All 3,883 annotation files byte-identical; 142 ROIs and 28 complete entries retained |

The live app returned HTTP 200 after restart. No physical reference value
was assumed and no user calibration lines were drawn. Existing tissue
completion states remain separate from the calibration measurement count.
Source, tests and generated documentation are included in the same local
commit; no changes were pushed.
