calibration_layer <- function() {
  at_layer("reference", labels = c("thickness", "other"),
           role = "calibration_reference")
}

calibration_line <- function(x, y = 0, label = "thickness", level = 0L) {
  at_roi_from_sf(sf::st_linestring(rbind(c(0, 0), c(x, y))),
                 label = label, level = level)
}

test_that("reference length uses at least three independent two-endpoint lines", {
  p <- at_project(tiny_image(), calibration_layer())
  image <- p$image
  for (i in seq_len(5L)) {
    p <- at_add_roi(p, "reference", calibration_line(i + 2))
    s <- .calibration_summary(p, "reference", "thickness")
    expect_identical(s$n, i)
    expect_equal(unname(s$lengths_px), seq(3, i + 2))
    if (i < 3L) expect_true(is.na(s$mean_px))
    else expect_equal(s$mean_px, mean(seq(3, i + 2)))
    expect_identical(s$status, if (i < 3L) "insufficient" else
      if (i < 5L) "minimum" else "recommended")
  }
  expect_equal(s$sd_px, stats::sd(3:7))
  expect_identical(p$image, image)
  p <- at_add_roi(p, "reference", calibration_line(10, label = "other"))
  p <- at_add_roi(p, "reference", at_roi_rect(0, 0, 2, 2, label = "thickness"))
  copied <- calibration_line(8); copied$source <- "copied"
  p <- at_add_roi(p, "reference", copied)
  s <- .calibration_summary(p, "reference", "thickness")
  expect_identical(s$n, 5L)
  expect_identical(s$excluded, 2L)
  expect_equal(s$mean_px, 5)
  p <- at_remove_roi(p, p$layers$reference$rois[[5]]$id)
  expect_identical(.calibration_summary(p, "reference", "thickness")$status,
                   "minimum")
})

test_that("reference length uses Euclidean distance at actual level zero", {
  img <- small_image()
  img$level_dims[[2]] <- c(50L, 25L)
  roi <- calibration_line(3, 4, level = 1L)
  expect_equal(.calibration_length(roi, img), sqrt(6^2 + 16^2))
  expect_equal(.calibration_length(calibration_line(3, 4), img), 5)
  roi$geometry <- sf::st_sfc(sf::st_linestring(rbind(c(1, 1), c(1, 1))))
  expect_true(is.na(.calibration_length(roi, img)))
  roi$geometry <- sf::st_sfc(sf::st_linestring(rbind(c(1, 1), c(2, 2), c(3, 3))))
  expect_true(is.na(.calibration_length(roi, img)))
  expect_true(is.na(.calibration_length(calibration_line(11), tiny_image())))
  roi$geometry <- sf::st_sfc(sf::st_linestring(rbind(c(1, 1), c(Inf, 2))))
  expect_true(is.na(.calibration_length(roi, img)))
})

test_that("copy previous does not manufacture calibration repeats", {
  p <- at_project(tiny_image(), list(calibration_layer(), at_layer("tissue")))
  p <- at_add_roi(p, "reference", calibration_line(3, 4))
  p <- at_add_roi(p, "tissue", at_roi_rect(1, 1, 2, 2, label = "cord"))
  to <- at_project(tiny_image(), list(calibration_layer(), at_layer("tissue")))
  copied <- .copy_forward(p, to)
  expect_length(copied$layers$reference$rois, 0L)
  expect_length(copied$layers$tissue$rois, 1L)
})

test_that("calibration defaults to line and follows saves, undo and redo", {
  skip_if_not_installed("shiny")
  testthat::local_mocked_bindings(.image_data_uri = function(...) NULL)
  s <- demo_session(1); s$autosave <- FALSE
  p <- at_project(tiny_image(), list(at_layer("tissue", labels = "cord"),
                                    calibration_layer()))
  rv <- shiny::reactiveValues(session = s, cursor = 1L, project = p,
                              tool = "polygon")
  .state_init(rv)
  shiny::testServer(mod_canvas_server, args = list(id = "canvas", rv = rv), {
    session$flushReact()
    rv$active_layer <- "reference"; rv$active_label <- "thickness"
    session$flushReact()
    expect_identical(rv$tool, "line")
    rv$display_ready <- TRUE
    event <- function(payload) c(.state_stamp(rv), list(payload = payload))
    drawn <- function(type, coords) {
      list(type = "Feature", geometry = list(type = type, coordinates = coords),
           properties = list(), target = list(layer = "reference", label = "thickness"))
    }
    for (i in 3:7) {
      session$setInputs(canvas_created = event(drawn("LineString", list(c(0, 0), c(i, 0)))))
    }
    expect_length(rv$project$layers$reference$rois, 5L)
    expect_match(output$calibration_summary$html, "5 / 5")
    expect_match(output$calibration_summary$html, "5.00 px")
    # Area/point tools cannot silently become calibration measurements.
    session$setInputs(canvas_created = event(drawn("Point", c(1, 1))))
    expect_length(rv$project$layers$reference$rois, 5L)
    # An edit into a degenerate segment is rejected too.
    id <- rv$project$layers$reference$rois[[1]]$id
    session$setInputs(canvas_edited = event(list(roi_id = id,
      geometry = list(type = "Point", coordinates = c(2, 2)))))
    expect_equal(.calibration_summary(rv$project, "reference", "thickness")$mean_px, 5)
    session$setInputs(undo = event(1))
    expect_length(rv$project$layers$reference$rois, 4L)
    session$setInputs(redo = event(1))
    expect_length(rv$project$layers$reference$rois, 5L)
    path <- tempfile(fileext = ".rds")
    at_save_project(rv$project, path)
    restored <- at_load_project(path)
    expect_equal(.calibration_summary(restored, "reference", "thickness")$mean_px, 5)
    rv$active_layer <- "tissue"; rv$active_label <- "cord"
    session$flushReact()
    expect_identical(rv$tool, "polygon")
  })
})
