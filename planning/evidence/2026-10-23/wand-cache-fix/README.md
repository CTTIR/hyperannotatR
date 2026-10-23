# A36: canvas script caching after local updates

The user reported that clicking the reflection wand did nothing. The updated
app reused `atcanvas-binding-0.3.0/atcanvas.js`, so a browser with the previous
script cached could display the new toolbar while running older drawing code.
The user's browser cache itself was not accessible for inspection.

Binding versions now incorporate the script SHA-256 digest, in both Shiny
output and standalone widgets. New script bytes therefore use a different
resource URL without requiring users to clear their browser cache.

| File | Command | Result |
| --- | --- | --- |
| regression-red.log | widget-canvas regression before implementation | Expected failure: content versioning absent |
| regression-green-final.log | Focused widget-canvas and app-drawing-tools tests | 101 pass, 0 warnings; 1 optional browser test skipped |
| browser-green.log | `NOT_CRAN=true Rscript tests/browser/drawing-tools.R` with Chromium | Trusted mouse clicks: point, round areas, reflection preview/discard/accept and saved geometry pass |
| install.log | `R CMD INSTALL` into an isolated library | Pass |
| live-verification.txt | Read restarted app HTML; compare all annotation files before/after package replacement | New script URL served; all 2576 annotation files identical; 104 ROIs and 24 completed entries preserved |

The browser test uses synthetic images and isolated annotation storage.
The Desktop deployment backed up the installed package and annotation directory.
No saved geometries, labels, completion states or raw images were changed.
