# Drawing controls and reflection proposals — 2026-10-23

The app adds three point display sizes, fixed 5/10/20 image-pixel circle
areas, and reviewed seed-based reflection proposals. Saved point geometries
remain points. Reflection growth uses the displayed RGB values, four-neighbour
connectivity and a bounded bright-region threshold; it is a drawing aid.

| File | Command | Result |
| --- | --- | --- |
| widget-red.log | New marker and circle node tests before implementation | 7 expected failures |
| drawing-red.log | New R drawing tests before implementation | 13 expected failures |
| widget-green.log | `node --test tests/audit/widget.test.js tests/audit/keyboard.test.js` | 56 pass |
| app-tests.log | `testthat::test_local` on app-builder, app-capabilities, app-drawing-tools, app-modules-extra and widget-events | 394 assertions pass; 1 environment warning from a non-writable Sass cache |
| app-modules-recheck.log | Re-run app-modules-extra with Sass cache in the test directory | 155 pass, 0 warnings |
| browser-qa.log | `NOT_CRAN=true Rscript tests/browser/drawing-tools.R` with Chromium | Pass: controls, checkpoint geometry, preview/discard/accept |
| install.log | `R CMD INSTALL` into an isolated library | Pass |

The browser runner is `tests/browser/drawing-tools.R`; it uses only a synthetic
image and an isolated annotation output. It checks actual visible selectors,
point size persistence, circle dimensions after checkpoint readback, and the
preview/discard/accept workflow with exact saved reflection pixel coverage.

No partner schema or stored identifier changes. Existing point masks retain
their single-pixel meaning. Reflection proposals never modify annotations or
completion status before explicit acceptance; stale proposals are rejected.
