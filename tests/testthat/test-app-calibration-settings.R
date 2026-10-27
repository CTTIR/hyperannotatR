reference_session <- function() {
  s <- demo_session(2)
  s$autosave <- FALSE
  s$layer_spec <- list(at_layer("Calibration", labels = "width",
    role = "calibration_reference", reference_assumptions_mm = list(width = 2)))
  s$projects <- lapply(seq_len(2), function(i) {
    png::writePNG(array(0.2, c(10, 10, 3)), s$manifest$path[i])
    p <- at_project(at_read_image(s$manifest$path[i]), s$layer_spec,
                     entry_id = s$manifest$entry_id[i])
    for (j in seq_len(3)) p <- at_add_roi(p, "Calibration",
      at_roi_from_sf(sf::st_linestring(rbind(c(0, j), c(5, j))), label = "width"))
    p
  })
  s$manifest$n_rois <- rep(3L, 2)
  s
}

test_that("global reference defaults and image overrides survive checkpoints", {
  s <- reference_session()
  s$meta$calibration_defaults_mm <- list(Calibration = list(width = 3))
  s$projects[[2]]$layers$Calibration$meta$reference_overrides_mm <- list(width = 4)
  summary <- function(s, i) .calibration_summary(at_current(at_goto(s, i)),
                                                "Calibration", "width")
  expect_equal(summary(s, 1)$assumed_length_mm, 3)
  expect_equal(summary(s, 1)$estimated_mm_per_px, 0.6)
  expect_equal(summary(s, 2)$assumed_length_mm, 4)
  expect_identical(summary(s, 2)$reference_source, "image")
  s <- .save_checkpoint(s, 1)
  resumed <- at_resume(file.path(s$out_dir, "_session.rds"))
  expect_equal(summary(resumed, 1)$assumed_length_mm, 3)
  expect_equal(summary(resumed, 2)$assumed_length_mm, 4)
  standalone <- at_load_project(resumed$manifest$project_path[1])
  expect_equal(.calibration_summary(standalone, "Calibration", "width")$assumed_length_mm, 3)
  # Changing the default also reaches disk-backed and previously unopened images.
  resumed$projects <- list(NULL, NULL)
  resumed$meta$calibration_defaults_mm$Calibration$width <- 5
  expect_equal(summary(resumed, 1)$assumed_length_mm, 5)
  expect_equal(summary(resumed, 2)$assumed_length_mm, 4)
  resumed$manifest$project_path[1] <- NA_character_
  expect_equal(summary(resumed, 1)$assumed_length_mm, 5)
})

test_that("reference entries respect scope, reset, history and browser intent", {
  skip_if_not_installed("shiny")
  testthat::local_mocked_bindings(.image_data_uri = function(...) NULL)
  s <- reference_session()
  rv <- shiny::reactiveValues(session = s, cursor = 1L, project = s$projects[[1]])
  .state_init(rv, load_project = .app_load_project)
  shiny::testServer(mod_canvas_server, args = list(id = "canvas", rv = rv), {
    session$flushReact()
    rv$display_ready <- TRUE
    event <- function(value, layer = "Calibration", label = "width") {
      c(.state_stamp(rv), list(payload = list(value = value, layer = layer, label = label)))
    }
    effective <- function() .calibration_summary(rv$project, "Calibration", "width",
      defaults = .calibration_defaults(rv))$assumed_length_mm
    expect_match(output$calibration_settings$html, "Global reference length")
    old_rois <- rv$project$layers$Calibration$rois
    stale <- event("9")
    session$setInputs(calibration_global_apply = event("3"))
    expect_equal(effective(), 3)
    expect_equal(rv$session$meta$calibration_defaults_mm$Calibration$width, 3)
    session$setInputs(calibration_image_apply = event("4"))
    expect_equal(effective(), 4)
    session$setInputs(calibration_global_apply = event("5"))
    expect_equal(effective(), 4)
    expect_match(output$calibration_summary$html, "Image override")
    for (invalid in c("", "0", "-1", "Inf", "NaN", "abc")) {
      session$setInputs(calibration_image_apply = event(invalid))
      expect_equal(effective(), 4)
    }
    session$setInputs(calibration_image_apply = stale)
    session$setInputs(calibration_image_apply = event("9", label = "missing"))
    expect_equal(effective(), 4)
    rv$read_only <- TRUE
    session$setInputs(calibration_global_apply = event("9"))
    session$setInputs(calibration_reset = event(""))
    expect_equal(effective(), 4)
    rv$read_only <- FALSE
    session$setInputs(calibration_reset = event(""))
    expect_equal(effective(), 5)
    expect_match(output$calibration_summary$html, "Global default")
    session$setInputs(undo = c(.state_stamp(rv), list(payload = 1)))
    expect_equal(effective(), 4)
    session$setInputs(redo = c(.state_stamp(rv), list(payload = 1)))
    expect_equal(effective(), 5)
    expect_identical(rv$project$layers$Calibration$rois, old_rois)
    expect_identical(rv$project$image$pixel_unit, "px")
    .state_navigate(rv, 2)
    expect_equal(effective(), 5)
    rv$display_ready <- TRUE
    rv$project$layers$Calibration$style$locked <- TRUE
    session$setInputs(calibration_image_apply = event("9"))
    session$setInputs(calibration_global_apply = event("9"))
    expect_equal(effective(), 5)
  })
})

test_that("another tab cannot overwrite a newer global default on save", {
  s <- reference_session()
  store <- .app_store(s)
  rv <- shiny::reactiveValues(session = s, cursor = 2L, project = s$projects[[2]],
                              store = store, session_generation = 0)
  .state_init(rv)
  shiny::isolate({
    store$session$meta$calibration_defaults_mm <- list(Calibration = list(width = 6))
    candidate <- .app_store_candidate(rv)
    expect_equal(candidate$meta$calibration_defaults_mm$Calibration$width, 6)
    expect_equal(.calibration_defaults(rv)$Calibration$width, 6)
    # Opening a standalone project retains its captured reference default.
    rv$store <- NULL
    rv$project$meta$calibration_defaults_mm <- list(Calibration = list(width = 7))
    expect_equal(.calibration_defaults(rv)$Calibration$width, 7)
  })
})
