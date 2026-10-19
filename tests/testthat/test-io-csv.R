test_that("CSV/WKT round-trips geometry and labels", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".csv")
  at_write_rois_csv(proj, p)
  lyr <- at_read_rois_csv(p)
  expect_identical(at_layer_n(lyr), 3L)
  g0 <- at_rois(proj)$geometry[[1]]
  g1 <- lyr$rois[[1]]$geometry[[1]]
  expect_equal(sf::st_coordinates(sf::st_sfc(g0)),
               sf::st_coordinates(sf::st_sfc(g1)), tolerance = 1e-6)
  expect_setequal(vapply(lyr$rois, `[[`, character(1), "label"),
                  at_rois(proj)$label)
})

test_that("at_read_rois_csv requires label and geometry columns", {
  p <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(data.frame(a = 1, b = 2), p, row.names = FALSE)
  expect_error(at_read_rois_csv(p), "label")
})

test_that("at_write_rois_csv refuses to clobber", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".csv")
  at_write_rois_csv(proj, p)
  expect_error(at_write_rois_csv(proj, p), "already exists")
})

test_that("empty project writes an empty CSV that reads back to an empty layer", {
  p <- withr::local_tempfile(fileext = ".csv")
  at_write_rois_csv(at_project(small_image()), p)
  lyr <- at_read_rois_csv(p)
  expect_identical(at_layer_n(lyr), 0L)
})

test_that("CSV writes level-0 coordinates labelled level 0 and round-trips area (A06)", {
  img <- new_annot_image("pyr.tif", "raster", c(64L, 64L), 2L,
                         list(c(64L, 64L), c(32L, 32L)), 1L)
  proj <- at_project(img, at_layer_add(at_layer("l"), at_roi_rect(0, 0, 3, 3, label = "a", level = 1L)))
  p <- withr::local_tempfile(fileext = ".csv")
  at_write_rois_csv(proj, p)
  df <- utils::read.csv(p, stringsAsFactors = FALSE)
  expect_identical(df$level, 0L)
  expect_identical(df$source_level, 1L)
  expect_identical(df$coordinate_schema, "annotatR-pixel-level-v1")
  lyr <- at_read_rois_csv(p)
  expect_identical(lyr$rois[[1]]$level, 0L)
  # 6 x 6 level-0 pixels, the area of a 3 x 3 square at level 1 of a 2x pyramid.
  expect_identical(at_rois(at_project(img, lyr))$area_px, 36)
})

test_that("CSVs from earlier hyperannotatR need an explicit level interpretation", {
  # Earlier writers labelled level-0 WKT with the ROI's own level and no schema.
  p <- withr::local_tempfile(fileext = ".csv")
  writeLines(c(
    '"roi_id","layer","label","level","area_px","author","source","created","modified","geometry"',
    '"r1","l","a",1,36,"me","manual","2024-01-01T00:00:00+0000","2024-01-01T00:00:00+0000","POLYGON ((0 0, 6 0, 6 6, 0 6, 0 0))"'
  ), p)
  expect_error(at_read_rois_csv(p), "Ambiguous legacy coordinate level")
  roi <- at_read_rois_csv(p, coordinate_level = 0L)$rois[[1]]
  expect_identical(roi$level, 0L)
  expect_equal(as.numeric(sf::st_area(roi$geometry)), 36)
  expect_identical(at_read_rois_csv(p, legacy_levels = "recorded")$rois[[1]]$level, 1L)
})

test_that("CSV keeps labels, ids and coordinates verbatim", {
  rois <- list(
    at_roi_rect(0, 0, 10 / 3, 10 / 7, label = "T", id = "007"),
    at_roi_rect(1, 1, 2, 2, label = "NA", id = "1e5")
  )
  lyr <- at_layer("l", labels = c("T", "NA"))
  for (r in rois) lyr <- at_layer_add(lyr, r)
  proj <- at_project(small_image(), lyr)
  p <- withr::local_tempfile(fileext = ".csv")
  at_write_rois_csv(proj, p)
  back <- at_read_rois_csv(p)
  expect_identical(vapply(back$rois, `[[`, character(1), "label"), c("T", "NA"))
  expect_identical(vapply(back$rois, `[[`, character(1), "id"), c("007", "1e5"))
  expect_identical(sf::st_coordinates(back$rois[[1]]$geometry),
                   sf::st_coordinates(rois[[1]]$geometry))
})

test_that("CSV restores the created and modified stamps it wrote", {
  r <- at_roi_rect(0, 0, 2, 2, label = "a")
  r$created <- as.POSIXct("2024-03-01 10:20:30", tz = "UTC")
  r$modified <- as.POSIXct("2024-03-02 11:21:31", tz = "UTC")
  p <- withr::local_tempfile(fileext = ".csv")
  at_write_rois_csv(at_project(small_image(), at_layer_add(at_layer("l"), r)), p)
  back <- at_read_rois_csv(p)$rois[[1]]
  expect_equal(as.numeric(back$created), as.numeric(r$created))
  expect_equal(as.numeric(back$modified), as.numeric(r$modified))
})
