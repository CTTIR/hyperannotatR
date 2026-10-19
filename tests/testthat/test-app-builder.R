skip_if_not_installed("shiny")
skip_if_not_installed("bslib")
skip_if_not_installed("shinyjs")
skip_if_not_installed("htmlwidgets")
skip_if_not_installed("magick")

rect_feature <- function(x0, y0, x1, y1) {
  list(type = "Feature", properties = list(),
       geometry = list(type = "Polygon",
                       coordinates = list(list(c(x0, y0), c(x1, y0), c(x1, y1), c(x0, y1), c(x0, y0)))))
}

# A browser envelope as the canvas and keys.js send it: the displayed entry
# and revision, and (for drawings) the displayed drawing target.
app_event <- function(rv, payload = 1) {
  if (!is.null(rv$project)) rv$display_ready <- TRUE
  if (is.list(payload) && identical(payload$type, "Feature")) {
    payload$target <- list(layer = rv$active_layer, label = rv$active_label)
  }
  list(entry_id = rv$entry_id, revision = rv$revision, payload = payload)
}

test_that("at_app builds an app object from explicit arguments without global options", {
  withr::local_options(hyperannotatR.session = NULL)
  app <- at_app(session = at_example_session(2))
  expect_s3_class(app, "shiny.appobj")
  expect_s3_class(at_app(input = at_example_project()), "shiny.appobj")
  expect_error(at_app(input = at_example_project(), session = at_example_session(1)), "not both")
  expect_error(at_app(control = "loopback"), "must be")
  expect_error(at_app(session = at_example_session(1), unexpected = 1))
  expect_null(getOption("hyperannotatR.session"))
})

test_that("the compatibility app directory builds through at_app", {
  app_dir <- system.file("shiny", "hyperannotatR", package = "hyperannotatR")
  expect_false(dir.exists(file.path(app_dir, "modules")))
  withr::local_options(hyperannotatR.session = at_example_session(1))
  appobj <- withr::with_dir(app_dir, source("app.R", local = new.env(parent = globalenv()))$value)
  expect_s3_class(appobj, "shiny.appobj")
})

test_that("navigation keeps unsaved edits in their own queue entry", {
  sess <- at_example_session(3)
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    expect_identical(rv$cursor, 1L)
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(10, 10, 60, 60)))
    expect_identical(nrow(at_rois(rv$project)), 1L)
    rid <- at_rois(rv$project)$roi_id
    session$setInputs(key_next = app_event(rv))
    expect_identical(rv$cursor, 2L)
    expect_identical(basename(rv$project$image$source), "image_02.png")
    expect_identical(nrow(at_rois(rv$project)), 0L)
    session$setInputs(key_prev = app_event(rv))
    expect_identical(rv$cursor, 1L)
    expect_identical(basename(rv$project$image$source), "image_01.png")
    expect_identical(at_rois(rv$project)$roi_id, rid)
    expect_identical(nrow(at_rois(rv$session$projects[[2]])), 0L)
  })
})

test_that("Shift+Enter files the project under its own entry and opens the next image (W1/A02)", {
  for (autosave in c(FALSE, TRUE)) {
    sess <- at_example_session(3)
    sess$autosave <- autosave
    shiny::testServer(.app_server(sess), {
      session$flushReact()
      session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(10, 10, 60, 60)))
      session$setInputs(key_commit_advance = app_event(rv))
      expect_identical(rv$cursor, 2L)
      expect_identical(basename(rv$project$image$source), "image_02.png")
      expect_identical(nrow(at_rois(rv$project)), 0L)
      expect_identical(basename(rv$session$projects[[1]]$image$source), "image_01.png")
      expect_identical(nrow(at_rois(rv$session$projects[[1]])), 1L)
      saved <- readRDS(file.path(sess$out_dir, "_session.rds"))
      expect_identical(saved$manifest$status[1:2], c("complete", "pending"))
      expect_identical(nrow(at_rois(saved$projects[[1]])), 1L)
      expect_identical(basename(saved$projects[[1]]$image$source), "image_01.png")
    })
  }
})

test_that("a reload or second tab continues from the latest in-memory state (W2)", {
  sess <- at_example_session(3)
  server <- .app_server(sess)
  shiny::testServer(server, {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(10, 10, 60, 60)))
    session$setInputs(key_next = app_event(rv))
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(5, 5, 30, 30)))
    expect_identical(rv$cursor, 2L)
  })
  # A new Shiny session of the same app object (a page reload).
  shiny::testServer(server, {
    session$flushReact()
    expect_identical(rv$cursor, 2L)
    expect_identical(nrow(at_rois(rv$project)), 1L)
    expect_identical(nrow(at_rois(rv$session$projects[[1]])), 1L)
    expect_identical(rv$session$manifest$n_rois[1:2], c(1L, 1L))
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(40, 40, 80, 80)))
    saved <- readRDS(file.path(sess$out_dir, "_session.rds"))
    expect_identical(vapply(saved$projects[1:2], function(p) nrow(at_rois(p)), integer(1)), c(1L, 2L))
  })
})

test_that("a resumed session shows its images and pixels (W4/A01)", {
  sess <- at_example_session(2)
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(10, 10, 60, 60)))
    session$setInputs(`session-save` = app_event(rv, list()))
  })
  resumed <- at_resume(file.path(sess$out_dir, "_session.rds"))
  expect_null(resumed$projects[[1]]$image$handle)
  shiny::testServer(.app_server(resumed), {
    session$flushReact()
    expect_identical(nrow(at_rois(rv$project)), 1L)
    expect_false(is.null(.image_data_uri(rv$project$image)))
    px <- at_tile(rv$project$image, xrange = c(1, 4), yrange = c(1, 4))
    expect_identical(dim(px)[1:2], c(4L, 4L))
  })
})

test_that("an older session file with more work is kept before the first overwrite", {
  sess <- at_example_session(2)
  first <- .app_server(sess)
  shiny::testServer(first, {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(10, 10, 60, 60)))
  })
  expect_length(list.files(sess$out_dir, "previous"), 0L)
  # Relaunching over the same folder from the original (empty) session.
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(1, 1, 5, 5)))
    session$setInputs(key_undo = app_event(rv))
  })
  kept <- list.files(sess$out_dir, "^_session-.*\\.previous\\.rds$", full.names = TRUE)
  expect_length(kept, 1L)
  expect_identical(nrow(at_rois(readRDS(kept)$projects[[1]])), 1L)
})

test_that("a misfiled project is refused on save and on load (identity tripwire)", {
  sess <- at_example_session(2)
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(10, 10, 60, 60)))
    # Simulate a transition bug that stored entry 1's project in slot 2.
    s <- rv$session; s$projects[[2]] <- rv$project; rv$session <- s
    st <- rv$store; st$session$projects[[2]] <- rv$project
    session$setInputs(`session-save` = app_event(rv, list()))
    expect_identical(rv$saved, "unsaved")
    expect_match(rv$save_error, "wrong queue entry")
    expect_false(file.exists(file.path(sess$out_dir, "_session.rds")))
    session$setInputs(key_next = app_event(rv))
    expect_null(rv$project)
    expect_match(rv$display_error, "does not match")
    expect_identical(rv$session$manifest$status[2], "skipped")
  })
})

test_that("read-only sessions refuse edits and drawing tools", {
  shiny::testServer(.app_server(at_example_session(1), read_only = TRUE), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(1, 1, 20, 20)))
    expect_identical(nrow(at_rois(rv$project)), 0L)
    session$setInputs(`canvas-tool_rect` = app_event(rv, list()))
    expect_identical(rv$tool, "pan")
    session$setInputs(`canvas-tool_probe` = app_event(rv, list()))
    expect_identical(rv$tool, "probe")
    expect_identical(.annotation_status(rv), "read_only")
  })
})

test_that("band views are validated, applied as display state only, and reset per image (W3)", {
  cube_dir <- withr::local_tempdir()
  file.copy(c(at_example_path("cube"), sub("\\.hdr$", ".dat", at_example_path("cube"))), cube_dir)
  file.copy(at_example_path("tissue"), file.path(cube_dir, "tissue.png"))
  sess <- at_session(file.path(cube_dir, c("example_cube.hdr", "tissue.png")), out_dir = cube_dir)
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    rev0 <- at_annotation_revision(rv$project)
    session$setInputs(`view-mode` = "normalized_difference", `view-b1` = "30", `view-b2` = "10",
                      `view-apply` = 1)
    expect_identical(rv$view, list(operation = "normalized_difference", bands = c(30L, 10L)))
    expect_identical(at_annotation_revision(rv$project), rev0)
    session$setInputs(`view-mode` = "single", `view-b1` = "99", `view-apply` = 2)
    expect_identical(rv$view$operation, "normalized_difference")
    session$setInputs(`canvas-canvas_probed` = app_event(rv, list(x = 5.5, y = 7.2)))
    expect_equal(unname(rv$probe), c(5.5, 7.2))
    sp <- .pixel_spectrum(rv$project$image, 5.5, 7.2)
    expect_identical(nrow(sp), 40L)
    expect_equal(sp$value, as.numeric(at_tile(rv$project$image, xrange = c(6, 6), yrange = c(8, 8))))
    # Bands 30 and 10 do not exist on the 3-band PNG: natural colour there.
    session$setInputs(key_next = app_event(rv))
    expect_identical(basename(rv$project$image$source), "tissue.png")
    expect_null(rv$view)
  })
})

test_that("a partner handoff is staged, shown and committed from the app", {
  proj <- at_example_project()
  handoff <- file.path(withr::local_tempdir(), "partner")
  partner <- at_add_roi(proj, "regions", at_roi_rect(5, 5, 40, 40, label = "stroma", id = "partner-1"))
  at_export_qupflowr(partner, handoff, formats = "qupath_geojson")
  sess <- at_example_session(1)
  sess$projects[[1]] <- proj
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    session$setInputs(`data-stage` = app_event(rv, list(handoff = handoff)))
    expect_s3_class(rv$staged, "at_staged_patch")
    expect_identical(rv$staged$summary$create, 1L)
    expect_identical(.annotation_status(rv), "staged")
    session$setInputs(`staging-commit` = app_event(rv, list()))
    expect_null(rv$staged)
    expect_true("partner-1" %in% at_rois(rv$project)$roi_id)
    session$flushReact()
    expect_identical(.annotation_status(rv), "committed")
    expect_gt(rv$revision, 0)
  })
})

hub_session <- function(n = 3) {
  h <- at_control_start(at_example_session(n), serve = FALSE)
  list(handle = h, hub = .control_hub(h))
}

test_that("an app attached to a control hub follows commands and reports its edits", {
  skip_if_not_installed("httpuv")
  ctl <- hub_session(3)
  h <- ctl$handle
  hub <- ctl$hub
  on.exit(at_control_stop(h), add = TRUE)
  shiny::testServer(.app_server(NULL, hub = hub), {
    session$flushReact()
    st <- at_control_state(h)
    at_control_command(h, list(operation = "context.goto", payload = list(queue_index = 3),
                               expected_revision = st$state_revision))
    session$elapse(600)
    expect_identical(rv$cursor, 3L)
    expect_identical(basename(rv$project$image$source), "image_03.png")
    st <- at_control_state(h)
    at_control_command(h, list(operation = "context.view",
                               payload = list(band_group = list(operation = "rgb", bands = list(3, 2, 1))),
                               expected_revision = st$state_revision))
    session$elapse(600)
    expect_identical(rv$view$bands, c(3L, 2L, 1L))
    before <- hub$revision
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(1, 1, 30, 30)))
    session$flushReact()
    expect_gt(hub$revision, before)
    expect_identical(hub$last_origin, "app")
    ev <- at_control_events(h)$events
    expect_identical(ev[[length(ev)]]$type, "annotations.edited")
    expect_identical(ev[[length(ev)]]$origin$kind, "app")
    expect_false(grepl(session$token %||% "no-token", ev[[length(ev)]]$origin$request_id, fixed = TRUE))
    expect_identical(length(at_control_state(h)$current$rois), 1L)
  })
})

test_that("app navigation never files one image's project under another hub entry (S1)", {
  skip_if_not_installed("httpuv")
  ctl <- hub_session(3)
  on.exit(at_control_stop(ctl$handle), add = TRUE)
  hub <- ctl$hub
  shiny::testServer(.app_server(NULL, hub = hub), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(1, 1, 30, 30)))
    session$setInputs(key_next = app_event(rv))
    session$flushReact()
    expect_identical(as.integer(hub$session$cursor), 2L)
    expect_identical(basename(hub$session$projects[[1]]$image$source), "image_01.png")
    expect_identical(nrow(at_rois(hub$session$projects[[1]])), 1L)
    p2 <- hub$session$projects[[2]]
    expect_true(is.null(p2) || basename(p2$image$source) == "image_02.png")
    expect_identical(at_control_state(ctl$handle)$current$image$source_name, "image_02.png")
  })
})

test_that("a controller goto does not misfile the app's previous image (S2)", {
  skip_if_not_installed("httpuv")
  ctl <- hub_session(3)
  on.exit(at_control_stop(ctl$handle), add = TRUE)
  h <- ctl$handle
  hub <- ctl$hub
  shiny::testServer(.app_server(NULL, hub = hub), {
    session$flushReact()
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(1, 1, 30, 30)))
    session$flushReact()
    at_control_command(h, list(operation = "context.goto", payload = list(queue_index = 2),
                               expected_revision = at_control_state(h)$state_revision))
    session$elapse(600)
    expect_identical(basename(rv$project$image$source), "image_02.png")
    expect_identical(basename(rv$session$projects[[1]]$image$source), "image_01.png")
    expect_identical(nrow(at_rois(rv$session$projects[[1]])), 1L)
    session$setInputs(key_prev = app_event(rv))
    session$flushReact()
    expect_identical(basename(rv$project$image$source), "image_01.png")
    expect_identical(nrow(at_rois(rv$project)), 1L)
    expect_identical(nrow(at_rois(hub$session$projects[[1]])), 1L)
    expect_identical(basename(hub$session$projects[[2]]$image$source), "image_02.png")
  })
})

test_that("a controller session.load replaces the app's queue (S3)", {
  skip_if_not_installed("httpuv")
  ctl <- hub_session(2)
  on.exit(at_control_stop(ctl$handle), add = TRUE)
  h <- ctl$handle
  hub <- ctl$hub
  file.copy(at_example_path("tissue"), file.path(hub$root, "new.png"))
  shiny::testServer(.app_server(NULL, hub = hub), {
    session$flushReact()
    at_control_command(h, list(operation = "session.load", payload = list(images = list("new.png")),
                               expected_revision = at_control_state(h)$state_revision))
    session$elapse(600)
    expect_identical(basename(rv$project$image$source), "new.png")
    expect_identical(nrow(rv$session$manifest), 1L)
    session$flushReact()
    p <- hub$session$projects[[1]]
    expect_true(is.null(p) || basename(p$image$source) == "new.png")
  })
})

test_that("an attached app refuses to load a folder over the hub's queue (S4)", {
  skip_if_not_installed("httpuv")
  ctl <- hub_session(3)
  on.exit(at_control_stop(ctl$handle), add = TRUE)
  hub <- ctl$hub
  d <- withr::local_tempdir()
  file.copy(at_example_path("tissue"), file.path(d, c("a.png", "b.png")))
  shiny::testServer(.app_server(NULL, hub = hub), {
    session$flushReact()
    session$setInputs(`data-load` = app_event(rv, list(dir = d)))
    session$flushReact()
    expect_match(output$`data-msg`, "control service")
    expect_identical(nrow(hub$session$manifest), 3L)
    expect_identical(nrow(rv$session$manifest), 3L)
  })
})

test_that("controller changes made before an app edit are applied, not overwritten (S5)", {
  skip_if_not_installed("httpuv")
  ctl <- hub_session(2)
  on.exit(at_control_stop(ctl$handle), add = TRUE)
  h <- ctl$handle
  hub <- ctl$hub
  shiny::testServer(.app_server(NULL, hub = hub), {
    session$flushReact()
    at_control_command(h, list(operation = "context.view", payload = list(tool = "rect"),
                               expected_revision = at_control_state(h)$state_revision))
    # The user draws before the 250 ms poll has seen the controller change.
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(1, 1, 30, 30)))
    session$flushReact()
    session$elapse(600)
    expect_identical(rv$tool, "rect")
    expect_identical(nrow(at_rois(hub$session$projects[[1]])), 1L)
    # A later app edit keeps the user's tool (no reset by unrelated revisions).
    session$setInputs(`canvas-tool_point` = app_event(rv, list()))
    session$setInputs(`canvas-canvas_created` = app_event(rv, rect_feature(40, 40, 60, 60)))
    session$elapse(600)
    expect_identical(rv$tool, "point")
  })
})

test_that("queue status changes in the app reach the hub with an event (S6)", {
  skip_if_not_installed("httpuv")
  ctl <- hub_session(3)
  on.exit(at_control_stop(ctl$handle), add = TRUE)
  hub <- ctl$hub
  shiny::testServer(.app_server(NULL, hub = hub), {
    session$flushReact()
    r0 <- hub$revision
    session$setInputs(key_flag = app_event(rv))
    session$flushReact()
    expect_identical(hub$session$manifest$status[1], "flagged")
    expect_gt(hub$revision, r0)
    ev <- at_control_events(ctl$handle)$events
    expect_true("queue.status_changed" %in% vapply(ev, `[[`, character(1), "type"))
  })
})

test_that("at_annotate builds through at_app and hands the app object to runApp", {
  captured <- NULL
  local_mocked_bindings(runApp = function(appDir, launch.browser, port, ...) {
    captured <<- list(app = appDir, launch.browser = launch.browser, port = port)
    invisible(NULL)
  }, .package = "shiny")
  withr::local_options(hyperannotatR.session = NULL)
  expect_message(expect_null(at_annotate(at_example_session(1), launch.browser = FALSE, port = 5555L)),
                 "temporary directory")
  expect_s3_class(captured$app, "shiny.appobj")
  expect_false(captured$launch.browser)
  expect_identical(captured$port, 5555L)
  expect_null(getOption("hyperannotatR.session"))
  expect_error(.check_app_pkgs(), NA)
  expect_true(.app_is_temp(file.path(tempdir(), "x")))
  expect_false(.app_is_temp(file.path(dirname(tempdir()), "hyperannotatR-not-temp")))
})
