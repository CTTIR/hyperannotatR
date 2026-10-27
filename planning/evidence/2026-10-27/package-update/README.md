# Package update — 2026-10-27

Fetched origin/main at `fa66716` and merged it into local `main` at `90fc5db`.
The two local drawing-tool and script-cache fixes are retained unchanged.
Package version remains 0.3.0. Local build-ignore, instruction and planning
edits were preserved. No commits were pushed.

| File | Command | Result |
| --- | --- | --- |
| install.log | `R CMD INSTALL` from a clean archive of the merged commit | Pass |
| tests.log | Focused io-npy, app-builder, app-drawing-tools and widget-canvas tests | 249 pass, 0 warnings; 3 expected optional skips |
| node.log | Canvas and keyboard node tests | 56 pass |
| browser.log | `tests/browser/drawing-tools.R` in isolated Chromium | Pass: real clicks, marker sizes, fixed areas, reflection proposal and persistence |
| deployment.json | Backup, install, restart and file-hash verification | 3854 annotation files unchanged; live HTTP responds with all drawing controls |
| compatibility.log | Resume current saved session with installed update and compare to pre-update snapshot | Identical manifest, metadata, labels, layers and ROIs; all 95 images materialize correctly |

The verified session had 142 saved ROIs and 28 completed entries. Browser QA
used synthetic inputs. Two workbench-reference NPY tests skipped because their
local dataset was absent; the optional combined widget-browser lane skipped,
while the dedicated drawing-tool browser runner passed.
