# Browser qualification

Run from the repository root. These runners drive a real Chromium through
Playwright against R fixtures that load this checkout with `pkgload`. They are
not part of `R CMD check`; `tests/testthat/test-app-browser.R` is the opt-in
shinytest2 lane.

Set `PLAYWRIGHT_MODULE` to a module path if Playwright is not installed in the
normal Node module search path. Set `CHROMIUM_PATH` to use a particular Chromium
executable (for example chromote's `chrome-headless-shell`). The defaults use
`require('playwright')` and Playwright's browser. `ANNOTATR_BROWSER_PORT` changes
a fixture port and `ANNOTATR_BROWSER_URL` the runner URL. Set
`ANNOTATR_BROWSER_ARTIFACT_DIR` to save screenshots and JSON evidence. Stop each
R fixture process when finished.

## Widget

```sh
Rscript tests/browser/widget-app.R      # port 5818
node tests/browser/widget.cjs
```

The R fixture uses the real canvas module and state transitions, two
independent Shiny outputs, and a synthetic SVG image. It does not require an
image decoder or private image files. The runner asserts even-odd hole pixels
and clicks, a MultiPolygon edit through Shiny that preserves IDs, attributes and
an anisotropic nonzero stored level, independent R proxy commands, stale event
rejection, actual DOM remount, gesture cancellation across render identity
changes, out-of-order real network image loads, a pending overlay surviving a
same-source render, and clearing a missing source. It waits for output state,
message acknowledgments, image callbacks and pixels; it has no fixed sleeps.

Fast behavioural tests (simulated canvas and keyboard, not browser
qualification):

```sh
node --test tests/audit/widget.test.js tests/audit/keyboard.test.js
```

## Browser protocol

Every browser action is an envelope `{entry_id, revision, payload}`: the queue
entry and annotation revision the user saw when acting. Widget renders and
annotation proxies carry `identity` (from the project's `meta$entry_id` and
`meta$annotation_revision`); the app passes the displayed drawing target as
`options.creationTarget = {layer, label, locked}`, and creation payloads include
that gesture-origin `target`. The server (`R/app-state.R`) applies an action only
when its identity is still the live one and rejects missing or invalid targets
instead of assigning a queued drawing to the current selection. Display-only
canvas events (probe, select, viewport) are envelopes too.

Product buttons built with `.at_action()` are intercepted by
`inst/shiny/hyperannotatR/www/keys.js`, which captures the fields listed in
`data-at-fields` at activation and stamps the rendered canvas identity. Only
explicit Next/Previous/Next-pending navigation uses the server stamp sent as the
`annotatr-state` message, which also disables edit controls until the canvas
reports a decoded image. Selection radios keep native Shiny behaviour and send
separate `*_intent` inputs carrying their original value and layer.
`window.atcanvasIdentity(id)` returns a copy of a mounted widget's rendered
entry/revision.

## Full app

`app-journey.R` builds the actual product UI (`.app_ui()`) and server
(`.app_server()`), creates public synthetic TIFF inputs (including missing,
corrupt and undecodable entries), and substitutes only the canvas image encoding
(`.image_data_uri()`) with a synthetic SVG. It uses real TIFF reads and real
checkpoints/exports in a temporary directory. `?resume=1` opens a new app over
the saved checkpoint through `at_resume()`.

```sh
Rscript tests/browser/app-journey.R     # port 5819
node tests/browser/app-journey.cjs
```

The runner uses a 1450×980 viewport and deviceScaleFactor 1.5, then resumes in a
1100×800 viewport. It exercises native Tab/radio focus, keyboard
point/rectangle/polygon geometry, undo/redo, a single Shift+Enter
commit/advance, failed-entry navigation, delayed action and form controls,
protected annotations, dirty failed-folder recovery, export download, and
reopening the actual checkpoint in a fresh browser session. A test-only
round-trip input (`fixture_ping`) provides barriers; there are no fixed sleeps.

`node tests/browser/action-origin.cjs` uses the same fixture to withhold canvas
renders while real Next, Complete, Save and Flag controls run. It verifies that
mutation and selection envelopes retain the displayed entry and revision, and
that saving retained annotations works after the current display fails.

All Shiny sessions of one app object share its in-memory queue (a reload
continues from the latest edits), so start a fresh `app-journey.R` for each
runner.

## Missing display encoder

For dependency-absence qualification, install the package into an isolated R
library containing its dependencies except `magick`, and set both `R_LIBS_USER`
and `R_LIBS_SITE` to that library. Verify `.libPaths()` and
`requireNamespace("magick", quietly = TRUE)` in that process. Do not remove or
alter packages in your normal libraries.

```sh
Rscript --vanilla tests/browser/minimal-app.R   # port 5820
node tests/browser/minimal.cjs
```

The fixture uses the installed package, with no function mocks: TIFF reads
succeed, the PNG example explains its reader requirement, and the browser shows
the missing canvas encoder before editing. This configuration is not a claim
about every optional-library combination or all browsers and accessibility
criteria.
