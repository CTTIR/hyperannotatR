test_that("point marker sizes persist without changing pixel membership", {
  for (radius in c(2, 4, 8)) {
    feature <- list(type = "Feature",
      geometry = list(type = "Point", coordinates = c(4.5, 3.5)),
      properties = list(attributes = list(point_radius = radius)))
    roi <- .feature_to_roi(feature, "a")
    expect_identical(roi$attributes$point_radius, radius)
    expect_equal(sum(as.matrix(at_mask(roi, dims = c(10, 10)))), 1)
    project <- at_project(tiny_image(), at_layer_add(at_layer("base"), roi))
    path <- tempfile(fileext = ".rds")
    at_save_project(project, path)
    restored <- at_load_project(path)
    expect_identical(restored$layers$base$rois[[1]]$attributes, roi$attributes)
    copied <- .copy_forward(project, at_project(tiny_image(), at_layer("base")))
    expect_identical(copied$layers$base$rois[[1]]$attributes$point_radius, radius)
  }
})

test_that("reflection growth keeps exact connected pixels, holes and image axes", {
  rgb <- array(0.2, c(20, 30, 3))
  rgb[3:7, 10:15, ] <- 0.98
  rgb[5, 12, ] <- 0.2
  rgb[12:14, 23:25, ] <- 0.98
  mask <- .reflection_membership(rgb, 10.5, 3.5, tolerance = 0.1)
  expected <- matrix(FALSE, 20, 30)
  expected[3:7, 10:15] <- TRUE
  expected[5, 12] <- FALSE
  expect_identical(mask, expected)
  roi <- .reflection_roi(mask, "reflectations")
  expect_equal(as.matrix(at_mask(roi, dims = c(30, 20))), expected)
  expect_true(sf::st_is_valid(roi$geometry))
  expect_equal(as.numeric(sf::st_area(roi$geometry)), 29)
  expect_error(.reflection_membership(rgb, 0, 0), class = "at_validation_error")
  expect_error(.reflection_membership(rgb, -1, 3), class = "at_validation_error")
  expect_error(.reflection_membership(array(1, c(20, 30, 3)), 5, 5),
               class = "at_limit_error")
})

test_that("reflection proposals require acceptance and cannot cross targets or revisions", {
  skip_if_not_installed("shiny")
  rgb <- array(0.2, c(10, 10, 3))
  rgb[3:4, 5:6, ] <- 0.98
  testthat::local_mocked_bindings(.image_data_uri = function(...) NULL,
    .view_display_array = function(...) rgb)
  s <- demo_session(1)
  s$autosave <- FALSE
  project <- at_project(tiny_image(), at_layer("Artifacts",
    labels = c("reflectations", "blood_overlay")))
  rv <- shiny::reactiveValues(session = s, cursor = 1L,
    project = project, tool = "reflection")
  .state_init(rv)
  shiny::testServer(mod_canvas_server, args = list(id = "canvas", rv = rv), {
    session$flushReact()
    rv$display_ready <- TRUE
    seed <- function() c(.state_stamp(rv), list(payload = list(x = 4.5, y = 2.5,
      target = list(layer = "Artifacts", label = "reflectations"))))
    session$setInputs(point_radius = "8", circle_radius = "2.5")
    expect_equal(rv$point_radius, 8)
    expect_equal(rv$circle_radius, 2.5)
    session$setInputs(canvas_reflection_seed = seed())
    expect_equal(nrow(at_rois(rv$project)), 0L)
    expect_equal(rv$reflection_preview$pixels, 4)
    old <- rv$reflection_preview$roi$id
    # Another click replaces the proposal: an old Accept button is rejected.
    session$setInputs(canvas_reflection_seed = seed())
    session$setInputs(accept_reflection = c(.state_stamp(rv),
      list(payload = list(preview_id = old))))
    expect_equal(nrow(at_rois(rv$project)), 0L)
    id <- rv$reflection_preview$roi$id
    session$setInputs(accept_reflection = c(.state_stamp(rv),
      list(payload = list(preview_id = id))))
    expect_equal(nrow(at_rois(rv$project)), 1L)
    expect_true(rv$project$layers$Artifacts$rois[[1]]$attributes$reviewed)
    expect_null(rv$reflection_preview)
    session$setInputs(canvas_reflection_seed = seed())
    rv$active_label <- "blood_overlay"
    session$flushReact()
    expect_null(rv$reflection_preview)
    rv$active_label <- "reflectations"
    session$setInputs(canvas_reflection_seed = seed())
    session$setInputs(discard_reflection = c(.state_stamp(rv),
      list(payload = list(preview_id = rv$reflection_preview$roi$id))))
    expect_null(rv$reflection_preview)
    expect_equal(nrow(at_rois(rv$project)), 1L)
    rv$read_only <- TRUE
    session$setInputs(canvas_reflection_seed = seed())
    expect_null(rv$reflection_preview)
  })
})

test_that("point sizes reject malformed values", {
  f <- list(geometry = list(type = "Point", coordinates = c(1, 1)))
  for (bad in list(NA_real_, Inf, -1, 0, c(2, 4), "large")) {
    f$properties <- list(attributes = list(point_radius = bad))
    expect_error(.feature_to_roi(f, "a"), class = "at_validation_error")
  }
})
