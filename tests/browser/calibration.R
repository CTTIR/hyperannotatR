# Isolated qualification: two-click calibration, repeated lengths and resume.
work <- Sys.getenv("ANNOTATR_BROWSER_ARTIFACT_DIR", tempfile("calibration-"))
dir.create(work, recursive = TRUE, showWarnings = FALSE)
repo <- normalizePath(".")
pkgload::load_all(repo, quiet = TRUE)
dir <- tempfile("browser-app-", tmpdir = work)
dir.create(dir)
rgb <- array(0.2, c(80, 120, 3))
rgb[, 31:40, ] <- 0.65
png::writePNG(rgb, file.path(dir, "fixture.png"))
s <- at_session(rep(file.path(dir, "fixture.png"), 2), layers = list(
  at_layer("tissue", labels = "cord"),
  at_layer("Calibration", labels = "Retractor thickness",
           role = "calibration_reference",
           reference_assumptions_mm = list("Retractor thickness" = 2))),
  out_dir = file.path(dir, "saved"), autosave = TRUE)
saveRDS(s, file.path(dir, "session.rds"))
writeLines(c(
  sprintf("pkgload::load_all(%s, quiet=TRUE)", deparse(repo)),
  sprintf("checkpoint <- %s", deparse(file.path(dir, "saved/_session.rds"))),
  sprintf("s <- if (file.exists(checkpoint)) hyperannotatR::at_resume(checkpoint) else readRDS(%s)",
          deparse(file.path(dir, "session.rds"))),
  "hyperannotatR::at_app(session=s)"), file.path(dir, "app.R"))
app <- shinytest2::AppDriver$new(dir, name = "calibration",
  load_timeout = 90000, timeout = 30000, width = 1500, height = 1200)
tryCatch({
  ready <- function() {
    app$wait_for_idle()
    app$wait_for_js("window.atcanvasInspect && window.atcanvasInspect('canvas-canvas') && window.atcanvasInspect('canvas-canvas').ready")
  }
  text <- function() app$get_js("document.getElementById('canvas-calibration_summary').textContent")
  choose <- function() {
    ready()
    app$run_js("document.querySelector('input[name=\"layers-layer\"][value=\"Calibration\"]').click()")
    app$wait_for_js("window.atcanvasInspect('canvas-canvas').tool === 'line'")
  }
  at <- function(x, y) {
    app$run_js("document.querySelector('#canvas-canvas canvas').scrollIntoView({block:'center', behavior:'instant'})")
    app$wait_for_js(sprintf(
      "(() => { const c = document.querySelector('#canvas-canvas canvas'); const p = window.atcanvasInspect('canvas-canvas').toClient(%f,%f); return document.elementFromPoint(p[0], p[1]) === c; })()",
      x, y))
    p <- app$get_js(sprintf("window.atcanvasInspect('canvas-canvas').toClient(%f,%f)", x, y))
    browser <- app$get_chromote_session()
    browser$Input$dispatchMouseEvent(type = "mousePressed",
      x = p[[1]], y = p[[2]], button = "left", clickCount = 1)
    browser$Input$dispatchMouseEvent(type = "mouseReleased",
      x = p[[1]], y = p[[2]], button = "left", clickCount = 1)
  }
  choose()
  stopifnot(grepl("0 / 5", text(), fixed = TRUE))
  stopifnot(grepl("Assumed reference length: 2.00 mm", text(), fixed = TRUE),
            !grepl("Estimated scale:", text(), fixed = TRUE))
  for (i in seq_len(5L)) {
    ready(); at(30, 5 + i * 10)
    stopifnot(app$get_value(export = "n_rois") == i - 1L)
    at(37 + i, 5 + i * 10)
    app$wait_for_value(export = "n_rois", ignore = list(i - 1L))
    stopifnot(app$get_value(export = "n_rois") == i)
    ready()
    if (i < 3) stopifnot(!grepl("Mean reference length", text(), fixed = TRUE))
    if (i == 3) stopifnot(grepl("9.00 px", text(), fixed = TRUE),
                           grepl("Minimum reached", text(), fixed = TRUE))
  }
  stopifnot(grepl("10.00 px", text(), fixed = TRUE),
            grepl("1.58 px", text(), fixed = TRUE),
            grepl("Estimated scale: 0.20000 mm/px", text(), fixed = TRUE),
            grepl("Recommended number reached", text(), fixed = TRUE))
  app$get_screenshot(file = file.path(work,
    paste0(basename(dir), "-five-measurements.png")))
  app$run_js("document.getElementById('canvas-undo').click()")
  app$wait_for_value(export = "n_rois", ignore = list(5L))
  ready(); stopifnot(grepl("4 / 5", text(), fixed = TRUE))
  app$run_js("document.getElementById('canvas-redo').click()")
  app$wait_for_value(export = "n_rois", ignore = list(4L))
  ready()
  saved <- at_resume(file.path(dir, "saved/_session.rds"))
  p <- at_current(saved)
  summary <- .calibration_summary(p, "Calibration", "Retractor thickness")
  stopifnot(summary$n == 5L, abs(summary$mean_px - 10) < 1e-6,
            max(abs(unname(summary$lengths_px) - 8:12)) < 1e-6,
            p$image$pixel_unit == "px", all(p$image$pixel_size == 1))
  reference <- function(scope, value, expected) {
    ready()
    app$run_js(sprintf(
      "document.getElementById('canvas-calibration_%s_mm').value = '%s'; document.getElementById('canvas-calibration_%s_apply').click()",
      scope, value, scope))
    app$wait_for_js(sprintf(
      "document.getElementById('canvas-calibration_summary').textContent.includes('Assumed reference length: %.2f mm')",
      expected))
    ready()
  }
  reference("global", 2.5, 2.5)
  reference("image", 3, 3)
  reference("global", 4, 3)
  stopifnot(grepl("Image override", text(), fixed = TRUE),
            grepl("Estimated scale: 0.30000 mm/px", text(), fixed = TRUE))
  app$run_js("document.getElementById('queue-nxt').click()")
  app$wait_for_value(export = "cursor", ignore = list(1L))
  choose()
  stopifnot(grepl("Assumed reference length: 4.00 mm", text(), fixed = TRUE),
            grepl("Global default", text(), fixed = TRUE))
  reference("image", 5, 5)
  app$run_js("document.getElementById('queue-prev').click()")
  app$wait_for_value(export = "cursor", ignore = list(2L))
  choose()
  stopifnot(grepl("Assumed reference length: 3.00 mm", text(), fixed = TRUE))
  app$run_js("document.getElementById('canvas-calibration_reset').click()")
  app$wait_for_js("document.getElementById('canvas-calibration_summary').textContent.includes('Assumed reference length: 4.00 mm')")
  ready()
  stopifnot(grepl("Global default", text(), fixed = TRUE))
  app$get_screenshot(file = file.path(work, paste0(basename(dir), "-reference-entry.png")))
  app$stop()
  app <- shinytest2::AppDriver$new(dir, name = "calibration-resume",
    load_timeout = 90000, timeout = 30000, width = 1500, height = 1200)
  choose()
  stopifnot(grepl("5 / 5", text(), fixed = TRUE),
            grepl("Estimated scale: 0.40000 mm/px", text(), fixed = TRUE),
            grepl("Global default", text(), fixed = TRUE),
            grepl("10.00 px", text(), fixed = TRUE))
  app$run_js("document.getElementById('queue-nxt').click()")
  app$wait_for_value(export = "cursor", ignore = list(1L))
  choose()
  stopifnot(grepl("Assumed reference length: 5.00 mm", text(), fixed = TRUE),
            grepl("Image override", text(), fixed = TRUE))
  app$run_js("document.querySelector('input[name=\"layers-layer\"][value=\"tissue\"]').click()")
  app$wait_for_js("window.atcanvasInspect('canvas-canvas').tool === 'pan'")
  cat("PASS: trusted two-click lines, automatic tool selection, minimum 3 / recommended 5,\n")
  cat("exact mean and SD, saved endpoints, undo/redo and fresh app resume.\n")
  cat("PASS: global and per-image reference entry, navigation, reset and persisted overrides.\n")
}, error = function(e) {
  message(conditionMessage(e))
  app$get_screenshot(file = file.path(work, paste0(basename(dir), "-failure.png")))
  writeLines(jsonlite::toJSON(app$get_js(
    "({height: innerHeight, width: innerWidth, canvas: document.querySelector('#canvas-canvas canvas').getBoundingClientRect().toJSON(), tool: window.atcanvasInspect('canvas-canvas').tool})"),
    auto_unbox = TRUE), file.path(work, paste0(basename(dir), "-failure.json")))
  stop(e)
}, finally = app$stop())
