# Server-level behaviour of the app modules that live in R/: data loading,
# layers, masks, spectra, region downloads, exports, sessions, staging and the
# UI tree. Assertions are on reactive state, rendered outputs and written files.
skip_if_not_installed("shiny")
skip_if_not_installed("bslib")
skip_if_not_installed("shinyjs")
skip_if_not_installed("htmlwidgets")
skip_if_not_installed("tiff")
skip_if_not(requireNamespace("magick", quietly = TRUE))

rect_feature <- function(x0, y0, x1, y1) {
  list(type = "Feature", properties = list(),
       geometry = list(type = "Polygon",
                       coordinates = list(list(c(x0, y0), c(x1, y0), c(x1, y1), c(x0, y1), c(x0, y0)))))
}

app_event <- function(rv, payload = 1) {
  if (!is.null(rv$project)) rv$display_ready <- TRUE
  if (is.list(payload) && identical(payload$type, "Feature")) {
    payload$target <- list(layer = rv$active_layer, label = rv$active_label)
  }
  list(entry_id = rv$entry_id, revision = rv$revision, payload = payload)
}

cube_session <- function() {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  file.copy(c(at_example_path("cube"), sub("\\.hdr$", ".dat", at_example_path("cube"))), d)
  file.copy(at_example_path("tissue"), file.path(d, "tissue.png"))
  at_session(c(file.path(d, "example_cube.hdr"), file.path(d, "tissue.png")),
             labels = c("tumour", "stroma"), out_dir = file.path(d, "out"))
}

test_that("the full UI tree renders every page, module and asset reference", {
  ui <- .app_ui()
  html <- as.character(htmltools::renderTags(ui)$html)
  for (id in c("queue-list", "canvas-canvas", "canvas-display", "canvas-undo", "canvas-copy",
               "view-mode", "mask-overlay", "region-download", "export-handoff", "export-outcome",
               "data-stage", "data-restore", "session-badge", "control-status", "help-show")) {
    expect_match(html, id, fixed = TRUE, label = id)
  }
  expect_match(html, "hyperannotatR-www/custom.css", fixed = TRUE)
  expect_match(html, "Impressum", fixed = TRUE)
  expect_match(html, "§ 5 DDG", fixed = TRUE)
  # Mutating controls carry the browser-intent marker; labels are present.
  expect_match(html, 'id="session-save"[^>]*data-at-action="true"', perl = TRUE)
  expect_match(html, 'id="layers-add_layer"[^>]*data-at-action="true"', perl = TRUE)
  expect_match(html, "New layer name", fixed = TRUE)
  expect_match(html, 'aria-label="Image annotation canvas"', fixed = TRUE)
  expect_false(grepl("btn-block", html, fixed = TRUE))
})

test_that("layers, labels, masks, overlap warnings and statistics respond to input", {
  sess <- cube_session()
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`layers-add_layer` = app_event(rv, list(new_layer = "artefact")))
    expect_true("artefact" %in% names(rv$project$layers))
    expect_identical(rv$active_layer, "artefact")
    session$setInputs(`layers-add_label` = app_event(rv, list(new_label = "blood", layer = "artefact")))
    expect_true("blood" %in% rv$project$layers$artefact$labels)
    expect_identical(rv$active_label, "blood")
    session$setInputs(`layers-layer_intent` = app_event(rv, list(value = "annotations")))
    expect_identical(rv$active_layer, "annotations")
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(2, 2, 40, 40)))
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(20, 20, 60, 60)))
    expect_identical(nrow(at_rois(rv$project)), 2L)
    session$setInputs(`mask-type` = "multiclass", `mask-overlap` = "first")
    expect_identical(rv$mask_type, "multiclass")
    expect_type(output$`mask-overlap_warn`, "list")
    stats <- output$`mask-stats`
    expect_match(stats, "tumour|annotations", perl = TRUE)
    session$setInputs(`mask-overlay` = TRUE)
    expect_true(rv$overlay_on)
    session$setInputs(`mask-export` = 1)
    stem <- .app_stems(rv$session)[1]
    expect_true(file.exists(file.path(sess$out_dir, "masks", paste0(stem, ".tif"))))
    # Edit and erase through the canvas contract keep ids and history.
    rid <- at_rois(rv$project)$roi_id[1]
    session$setInputs(`canvas-canvas_edited` = app_event(rv, list(roi_id = rid, layer = "annotations",
                                                                  label = "tumour",
                                                                  geometry = rect_feature(5, 5, 30, 30)$geometry)))
    expect_true(rid %in% at_rois(rv$project)$roi_id)
    session$setInputs(`canvas-canvas_erased` = app_event(rv, rid))
    expect_false(rid %in% at_rois(rv$project)$roi_id)
    session$setInputs(key_undo = app_event(rv))
    expect_true(rid %in% at_rois(rv$project)$roi_id)
    session$setInputs(key_redo = app_event(rv))
    expect_false(rid %in% at_rois(rv$project)$roi_id)
    keep <- at_rois(rv$project)$roi_id[1]
    session$setInputs(`roitable-select` = app_event(rv, list(del_id = keep)))
    expect_identical(rv$selection, keep)
    session$setInputs(`canvas-canvas_selected` = app_event(rv, list("x")))
    expect_identical(rv$selection, "x")
    session$setInputs(`canvas-canvas_viewport` = app_event(rv, list(bounds = list(1, 2, 30, 40))))
    expect_equal(rv$viewport, c(1, 2, 30, 40))
    expect_match(output$`roitable-table`, "unreviewed")
    session$setInputs(key_tool = app_event(rv, "polygon"))
    session$setInputs(key_label = app_event(rv, 1))
    session$setInputs(key_flag = app_event(rv))
    expect_identical(rv$tool, "polygon")
    expect_identical(at_session_status(rv$session)$status[1], "flagged")
    session$setInputs(key_delete = app_event(rv))
    expect_identical(nrow(at_rois(rv$project)), 0L)
  })
})

test_that("edits keep ROI identity and provenance, and a click without a drag is not an edit (W24)", {
  sess <- cube_session()
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(2, 2, 10, 10)))
    roi <- rv$project$layers$annotations$rois[[1]]
    rev <- rv$revision
    session$setInputs(`canvas-canvas_edited` = app_event(rv, list(roi_id = roi$id,
                                                                  geometry = rect_feature(2, 2, 10, 10)$geometry)))
    expect_identical(rv$revision, rev)
    expect_length(rv$undo, 1L)
    session$setInputs(`canvas-canvas_edited` = app_event(rv, list(roi_id = roi$id, label = "stroma",
                                                                  geometry = rect_feature(3, 3, 12, 12)$geometry)))
    edited <- rv$project$layers$annotations$rois[[1]]
    expect_identical(edited$id, roi$id)
    expect_identical(edited$label, roi$label)
    expect_identical(edited$author, roi$author)
    expect_identical(edited$source, roi$source)
    expect_identical(edited$created, roi$created)
    expect_equal(at_roi_area(edited), 81)
  })
})

test_that("observer errors are reported instead of ending the session (W5)", {
  sess <- cube_session()
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`layers-add_layer` = app_event(rv, list(new_layer = "extra")))
    expect_identical(rv$active_layer, "extra")
    session$setInputs(key_undo = app_event(rv))
    # The undone layer is gone; the active layer follows the project.
    expect_false("extra" %in% names(rv$project$layers))
    expect_identical(rv$active_layer, "annotations")
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(2, 2, 10, 10)))
    expect_identical(nrow(at_rois(rv$project)), 1L)
    # A mutation that errors is refused with a notification, not an error.
    expect_no_error(.state_mutate(rv, function(p) stop("injected failure")))
    expect_identical(nrow(at_rois(rv$project)), 1L)
    # A drawing for an unknown layer is refused.
    bad <- app_event(rv, rect_feature(20, 20, 30, 30))
    bad$payload$target$layer <- "gone"
    session$setInputs(`canvas-canvas_created` = bad)
    expect_identical(nrow(at_rois(rv$project)), 1L)
  })
})

test_that("a failed image load clears the previous image's history (W6)", {
  d <- withr::local_tempdir()
  file.copy(at_example_path("tissue"), file.path(d, "good.png"))
  writeLines("not an image", file.path(d, "broken.png"))
  sess <- at_session(file.path(d, c("good.png", "broken.png")), labels = "a", out_dir = file.path(d, "out"))
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(2, 2, 10, 10)))
    session$setInputs(key_next = app_event(rv))
    expect_null(rv$project)
    expect_length(rv$undo, 0L)
    expect_identical(rv$session$manifest$status[2], "skipped")
    session$setInputs(key_undo = app_event(rv))
    expect_null(rv$project)
    expect_identical(nrow(at_rois(rv$session$projects[[1]])), 1L)
  })
})

test_that("locked layers and protected ROIs refuse every ingress (W9)", {
  sess <- cube_session()
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(2, 2, 10, 10)))
    id <- at_rois(rv$project)$roi_id
    p <- rv$project
    p$layers$annotations$style$locked <- TRUE
    rv$project <- p
    rev <- rv$revision
    session$setInputs(`canvas-canvas_erased` = app_event(rv, id))
    session$setInputs(key_delete = app_event(rv))
    session$setInputs(`roitable-delete` = app_event(rv, list(del_id = id)))
    session$setInputs(`canvas-canvas_edited` = app_event(rv, list(roi_id = id,
                                                                  geometry = rect_feature(3, 3, 9, 9)$geometry)))
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(20, 20, 30, 30)))
    expect_identical(at_rois(rv$project)$roi_id, id)
    expect_identical(rv$revision, rev)
  })
})

test_that("spectra follow the selected source and the cube status reports metadata", {
  sess <- cube_session()
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(10, 10, 30, 30)))
    expect_match(output$`view-status`, "spectral")
    expect_match(output$`view-status`, "450-900 nm")
    expect_match(output$`view-status`, "bytes read so far")
    for (mode in c("rgb", "ratio", "band_mean", "wavelength_window_mean", "single", "natural")) {
      session$setInputs(`view-mode` = mode)
      expect_no_error(output$`view-band_inputs`)
    }
    session$setInputs(`view-mode` = "wavelength_window_mean", `view-wmin` = 500, `view-wmax` = 600,
                      `view-apply` = 1)
    expect_identical(rv$view$operation, "wavelength_window_mean")
    session$setInputs(`view-mode` = "natural", `view-apply` = 2)
    expect_null(rv$view)
  })
  proj <- at_project(at_read_image(sess$manifest$path[1]),
                     at_layer_add(at_layer("annotations", labels = "tumour"),
                                  at_roi_rect(10, 10, 30, 30, label = "tumour", id = "r1")))
  rv <- shiny::reactiveValues(project = proj, probe = NULL)
  shiny::testServer(mod_spectrum_server, args = list(id = "sp", rv = rv), {
    expect_no_error(output$panel)
    session$setInputs(source = "layer", layer = "annotations")
    expect_identical(nrow(spectra()), 40L)
    session$setInputs(source = "roi", roi = "r1")
    expect_identical(unique(spectra()$roi_id), "r1")
    rv$probe <- c(x = 3, y = 4)
    session$setInputs(source = "pixel")
    expect_identical(spectra()$roi_id[1], "pixel(4,5)")
    expect_equal(spectra()$value, as.numeric(at_tile(proj$image, xrange = c(4, 4), yrange = c(5, 5))))
    expect_match(output$caption, "original cube")
    expect_no_error(output$source_sel)
  })
})

test_that("band selections survive annotation edits (W22)", {
  sess <- cube_session()
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`view-mode` = "rgb")
    session$setInputs(`view-b1` = "35", `view-b2` = "20", `view-b3` = "5")
    html <- as.character(output$`view-band_inputs`$html)
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(2, 2, 10, 10)))
    expect_identical(nrow(at_rois(rv$project)), 1L)
    # The controls are not rebuilt (which would reset them to the defaults).
    expect_identical(as.character(output$`view-band_inputs`$html), html)
    # When they are rebuilt (a new mode), valid choices are kept.
    session$setInputs(`view-mode` = "ratio")
    rebuilt <- as.character(output$`view-band_inputs`$html)
    expect_match(rebuilt, '<option value="35" selected>', fixed = TRUE)
    expect_match(rebuilt, '<option value="20" selected>', fixed = TRUE)
  })
})

test_that("the Summary page explains empty masks and spectra instead of blank plots", {
  sess <- cube_session()
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    expect_no_error(output$`mask-preview`)
    m <- .current_mask(rv)
    expect_identical(nrow(at_rois(rv$project)), 0L)
    expect_s3_class(.message_plot("x"), "ggplot")
  })
  proj <- at_example_project()
  rv <- shiny::reactiveValues(project = proj, probe = NULL)
  shiny::testServer(mod_spectrum_server, args = list(id = "sp", rv = rv), {
    expect_match(as.character(output$panel$html), "spectral images")
  })
})

test_that("region downloads, exports and handoffs write verifiable files", {
  sess <- cube_session()
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(4, 4, 12, 10)))
    rid <- at_rois(rv$project)$roi_id
    rv$selection <- rid
    session$setInputs(`region-extent` = "roi")
    zip_path <- output$`region-download`
    files <- utils::unzip(zip_path, list = TRUE)$Name
    expect_setequal(files, c("region.dat", "region.hdr", "region.json"))
    ex <- withr::local_tempdir()
    utils::unzip(zip_path, exdir = ex)
    expect_equal(at_tile(at_read_image(file.path(ex, "region.hdr"))),
                 at_tile(rv$project$image, xrange = c(5, 12), yrange = c(5, 10)), tolerance = 0)
    meta <- jsonlite::read_json(file.path(ex, "region.json"))
    expect_false(meta$display_product)
    expect_identical(meta$bounds$xmax, 12L)
    session$setInputs(`region-extent` = "custom", `region-xmin` = 0, `region-ymin` = 0,
                      `region-xmax` = 5000, `region-ymax` = 5000)
    expect_setequal(utils::unzip(output$`region-download`, list = TRUE)$Name,
                    c("region.dat", "region.hdr", "region.json"))
    # A region outside the image downloads an explanation, not a failure (W27).
    session$setInputs(`region-xmin` = 6000, `region-xmax` = 7000)
    expect_identical(utils::unzip(output$`region-download`, list = TRUE)$Name, "README.txt")
    session$setInputs(`export-formats` = c("mask_tiff", "geojson", "qupath", "csv"), `export-scope` = "current")
    exp_zip <- output$`export-run`
    session$flushReact()
    stem <- .app_stems(rv$session)[1]
    expect_setequal(utils::unzip(exp_zip, list = TRUE)$Name,
                    c(paste0(stem, c(".tif", ".tif.legend.json", ".geojson", "_qupath.geojson", "_rois.csv")),
                      "_export_manifest.csv"))
    expect_match(output$`export-outcome`, "4 complete; 0 failed; 0 skipped")
    session$setInputs(`export-handoff_name` = "partner/../h1", `export-handoff` = 1)
    expect_match(output$`export-handoff_status`, "digest")
    expect_true(file.exists(file.path(sess$out_dir, "handoff")))
    hz <- output$`export-handoff_zip`
    expect_true("integrity.json" %in% utils::unzip(hz, list = TRUE)$Name)
  })
})

test_that("an export for a skipped current image still covers the other images (W27)", {
  d <- withr::local_tempdir()
  file.copy(at_example_path("tissue"), file.path(d, "good.png"))
  writeLines("not an image", file.path(d, "broken.png"))
  sess <- at_session(file.path(d, c("good.png", "broken.png")), labels = "a", out_dir = file.path(d, "out"))
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(2, 2, 10, 10)))
    session$setInputs(key_next = app_event(rv))
    expect_null(rv$project)
    session$setInputs(`export-formats` = "geojson", `export-scope` = "all")
    names <- utils::unzip(output$`export-run`, list = TRUE)$Name
    session$flushReact()
    expect_true(any(grepl("\\.geojson$", names)))
    expect_match(output$`export-outcome`, "1 complete")
  })
})

test_that("sessions save, complete, flag and reload from the data page", {
  sess <- cube_session()
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(1, 1, 9, 9)))
    session$setInputs(`session-save` = app_event(rv, list()))
    expect_identical(rv$saved, "saved")
    expect_true(file.exists(file.path(sess$out_dir, "_session.rds")))
    expect_match(output$`session-saved`, "checkpoint")
    saved <- at_load_session(file.path(sess$out_dir, "_session.rds"))
    expect_null(saved$projects[[1]]$image$handle)
    session$setInputs(`session-complete` = app_event(rv, list()))
    expect_identical(at_session_status(rv$session)$status[1], "complete")
    session$setInputs(`session-flag` = app_event(rv, list()))
    expect_identical(at_session_status(rv$session)$status[1], "flagged")
    expect_match(as.character(output$`session-badge`$html), "saved")
    session$setInputs(key_commit_advance = app_event(rv))
    expect_identical(rv$cursor, 2L)
    expect_identical(at_session_status(rv$session)$status[1], "complete")
    session$setInputs(key_next_pending = app_event(rv))
    session$setInputs(key_save = app_event(rv))
    session$setInputs(key_help = app_event(rv))
    session$setInputs(key_paste_forward = app_event(rv))
    expect_identical(nrow(at_rois(rv$project)), 1L)
    expect_match(output$`dashboard-status`, "complete")
    expect_type(output$`dashboard-tiles`, "list")
    session$setInputs(`queue-filter` = "complete")
    expect_match(output$`queue-list`, "✓")
    expect_match(output$`queue-progress`, "/ 2 complete")
    session$setInputs(`data-load` = app_event(rv, list(dir = "/no/such/folder")))
    expect_identical(output$`data-msg`, "Folder not found.")
    empty <- withr::local_tempdir()
    session$setInputs(`data-load` = app_event(rv, list(dir = empty)))
    expect_match(output$`data-msg`, "No supported images")
    folder <- withr::local_tempdir()
    file.copy(at_example_path("tissue"), file.path(folder, c("a.png", "b.png")))
    gen <- rv$session_generation
    session$setInputs(`data-load` = app_event(rv, list(dir = folder)))
    expect_match(output$`data-msg`, "Loaded 2 image")
    expect_identical(rv$session_generation, gen + 1)
    expect_identical(nrow(rv$session$manifest), 2L)
    expect_identical(basename(rv$project$image$source), "a.png")
    expect_match(output$`data-table`, "a")
    session$setInputs(`data-stage` = app_event(rv, list(handoff = "/missing")))
    expect_identical(output$`data-stage_msg`, "Handoff not found.")
  })
})

test_that("folder loads skip ENVI payloads, bound the listing and honour app_root (W12/W17)", {
  d <- withr::local_tempdir()
  file.copy(c(at_example_path("cube"), sub("\\.hdr$", ".dat", at_example_path("cube"))), d)
  file.copy(at_example_path("tissue"), file.path(d, "tissue.png"))
  deep <- file.path(d, "a", "b", "c", "d", "e", "f")
  dir.create(deep, recursive = TRUE)
  file.copy(at_example_path("tissue"), file.path(deep, "deep.png"))
  files <- .app_list_images(d)
  expect_setequal(basename(files), c("example_cube.hdr", "tissue.png"))
  expect_length(.app_list_images(d, max_files = 1L), 1L)
  expect_true(attr(.app_list_images(d, max_files = 1L), "truncated"))
  withr::local_options(hyperannotatR.app_root = file.path(d, "a"))
  expect_false(.app_path_allowed(d))
  expect_true(.app_path_allowed(deep))
  sess <- cube_session()
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`data-load` = app_event(rv, list(dir = d)))
    expect_match(output$`data-msg`, "outside the folder")
  })
})

test_that("a dirty folder replacement keeps the previous queue for recovery", {
  sess <- cube_session()
  sess$autosave <- FALSE
  folder <- withr::local_tempdir()
  file.copy(at_example_path("tissue"), file.path(folder, "a.png"))
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(1, 1, 9, 9)))
    session$setInputs(`data-load` = app_event(rv, list(dir = folder)))
    expect_identical(nrow(rv$session$manifest), 1L)
    expect_match(output$`data-recovery`, "retained")
    expect_false(identical(rv$session$out_dir, sess$out_dir))
    session$setInputs(`data-restore` = app_event(rv, list()))
    expect_identical(nrow(rv$session$manifest), 2L)
    expect_identical(nrow(at_rois(rv$project)), 1L)
    expect_identical(rv$saved, "unsaved")
  })
})

test_that("the badge is the one state indicator and counts unsaved images (W15)", {
  sess <- at_example_session(3)
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    expect_match(output$`session-saved`, "no checkpoint yet")
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(1, 1, 9, 9)))
    session$setInputs(key_next = app_event(rv))
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(1, 1, 9, 9)))
    expect_match(as.character(output$`session-badge`$html), "unsaved (2 images)", fixed = TRUE)
    expect_false(grepl("unsaved", output$`session-saved`))
    session$setInputs(`session-save` = app_event(rv, list()))
    expect_match(as.character(output$`session-badge`$html), ">saved<", fixed = TRUE)
    expect_match(output$`session-saved`, "checkpoint [0-9:]{8}")
  })
})

test_that("staged patches can be discarded and stale commits are refused", {
  proj <- at_example_project()
  handoff <- file.path(withr::local_tempdir(), "partner")
  at_export_qupflowr(at_add_roi(proj, "regions", at_roi_rect(1, 1, 9, 9, label = "stroma", id = "p-1")),
                     handoff, formats = "qupath_geojson")
  sess <- at_example_session(1)
  sess$projects[[1]] <- proj
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`data-stage` = app_event(rv, list(handoff = handoff)))
    expect_match(output$`staging-ops`, "p-1")
    session$setInputs(`staging-discard` = app_event(rv, list()))
    expect_null(rv$staged)
    session$setInputs(`data-stage` = app_event(rv, list(handoff = handoff)))
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(50, 50, 70, 70)))
    session$setInputs(`staging-commit` = app_event(rv, list()))
    expect_false("p-1" %in% at_rois(rv$project)$roi_id)
    expect_s3_class(rv$staged, "at_staged_patch")
  })
})

test_that("the dashboard plots counts from zero with whole-number breaks", {
  expect_identical(.integer_breaks(c(-0.05, 0.05)), c(0, 1))
  expect_true(all(.integer_breaks(c(0, 7)) == round(.integer_breaks(c(0, 7)))))
  sess <- at_example_session(2)
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    expect_no_error(output$`dashboard-plot`)
  })
})

test_that("the control status panel reports the attached hub", {
  skip_if_not_installed("httpuv")
  h <- at_control_start(at_example_session(1), serve = FALSE)
  on.exit(at_control_stop(h), add = TRUE)
  shiny::testServer(mod_control_status_server, args = list(id = "c", rv = shiny::reactiveValues(),
                                                           hub = .control_hub(h)), {
    expect_match(as.character(output$status$html), "control: running")
  })
  shiny::testServer(mod_control_status_server, args = list(id = "c", rv = shiny::reactiveValues(), hub = NULL), {
    expect_null(output$status)
  })
})
