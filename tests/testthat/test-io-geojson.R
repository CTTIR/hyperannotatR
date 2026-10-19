test_that("GeoJSON round-trips geometry to 1e-9 and preserves metadata", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  back <- at_read_geojson(p)
  expect_setequal(names(back), c("tissue", "tumour"))
  g0 <- proj$layers$tissue$rois[[1]]$geometry
  g1 <- back$tissue$rois[[1]]$geometry
  expect_equal(sf::st_coordinates(g0), sf::st_coordinates(g1), tolerance = 1e-9)
  expect_setequal(
    vapply(back$tissue$rois, `[[`, character(1), "label"),
    vapply(proj$layers$tissue$rois, `[[`, character(1), "label")
  )
})

test_that("GeoJSON preserves labels, ids, source, and level", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  back <- at_read_geojson(p)
  roi <- back$tumour$rois[[1]]
  expect_identical(roi$label, "tumour")
  expect_identical(roi$level, 0L)
  expect_identical(roi$source, "manual")
})

test_that("flip_y is invertible in both directions", {
  proj <- demo_project()
  h <- at_dims(proj$image, 0)[2]
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p, flip_y = TRUE)
  back <- at_read_geojson(p, flip_y = TRUE, height = h)
  g0 <- proj$layers$tissue$rois[[1]]$geometry
  g1 <- back$tissue$rois[[1]]$geometry
  expect_equal(sf::st_coordinates(g0), sf::st_coordinates(g1), tolerance = 1e-9)
})

test_that("at_read_geojson errors when flip_y lacks height", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  expect_error(at_read_geojson(p, flip_y = TRUE), "height")
})

test_that("at_write_geojson refuses to clobber", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  expect_error(at_write_geojson(proj, p), "already exists")
})

test_that("point and polygon geometries both round-trip", {
  lyr <- at_layer_add(at_layer_add(at_layer("l"),
                                   at_roi_point(3, 4, label = "pt")),
                      at_roi_rect(0, 0, 5, 5, label = "rect"))
  proj <- at_project(small_image(), lyr)
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  back <- at_read_geojson(p, layer_name = "l")
  types <- vapply(back$rois, function(r) as.character(sf::st_geometry_type(r$geometry)), character(1))
  expect_setequal(types, c("POINT", "POLYGON"))
})

# A two-level pyramid (64 -> 32 px) with one ROI stored at level 1 whose
# level-0 area is 6 x 6 = 36 px, independently of any hyperannotatR rasteriser.
level1_project <- function() {
  img <- new_annot_image("pyr.tif", "raster", c(64L, 64L), 2L,
                         list(c(64L, 64L), c(32L, 32L)), 1L)
  at_project(img, at_layer_add(at_layer("l"), at_roi_rect(0, 0, 3, 3, label = "a", level = 1L)))
}

test_that("GeoJSON records the coordinate level it wrote and round-trips area (A06)", {
  proj <- level1_project()
  expect_identical(at_rois(proj)$area_px, 36)
  for (lv in 0:1) {
    p <- withr::local_tempfile(fileext = ".geojson")
    at_write_geojson(proj, p, level = lv)
    props <- jsonlite::read_json(p)$features[[1]]$properties
    expect_identical(props$level, lv, info = lv)
    expect_identical(props$source_level, 1L, info = lv)
    expect_identical(props$coordinate_schema, "annotatR-pixel-level-v1", info = lv)
    back <- at_read_geojson(p)$l
    expect_identical(back$rois[[1]]$level, lv, info = lv)
    expect_identical(at_rois(at_project(proj$image, back))$area_px, 36, info = lv)
  }
})

test_that("bare feature arrays and single Features are read, null geometries skipped", {
  feat <- '{"type":"Feature","geometry":{"type":"Point","coordinates":[1,2]},"properties":{"label":"a","layer":7}}'
  p <- withr::local_tempfile(fileext = ".geojson")
  writeLines(paste0("[", feat, "]"), p)
  arr <- at_read_geojson(p)
  expect_identical(names(arr), "7")
  expect_identical(at_layer_n(arr[["7"]]), 1L)
  writeLines(feat, p)
  expect_identical(at_layer_n(at_read_geojson(p)[["7"]]), 1L)
  writeLines(paste0('{"type":"FeatureCollection","features":[', feat,
                    ',{"type":"Feature","geometry":null,"properties":{"label":"b"}}]}'), p)
  expect_warning(fc <- at_read_geojson(p), "without a geometry")
  expect_identical(at_layer_n(fc[["7"]]), 1L)
})

test_that("documents that are not GeoJSON features are refused with a code", {
  p <- withr::local_tempfile(fileext = ".geojson")
  writeLines('{"hello": 1}', p)
  err <- tryCatch(at_read_geojson(p), error = function(e) e)
  expect_s3_class(err, "at_validation_error")
  expect_identical(err$code, "INVALID_GEOJSON")
  writeLines("{not json", p)
  expect_identical(tryCatch(at_read_geojson(p), error = function(e) e$code), "INVALID_JSON")
})

test_that("GeoJSON restores the created and modified stamps it wrote", {
  r <- at_roi_rect(0, 0, 2, 2, label = "a")
  r$created <- as.POSIXct("2024-03-01 10:20:30", tz = "UTC")
  r$modified <- as.POSIXct("2024-03-02 11:21:31", tz = "UTC")
  proj <- at_project(small_image(), at_layer_add(at_layer("l"), r))
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  back <- at_read_geojson(p)$l$rois[[1]]
  expect_equal(as.numeric(back$created), as.numeric(r$created))
  expect_equal(as.numeric(back$modified), as.numeric(r$modified))
})

test_that("a nonzero level without the coordinate schema is ambiguous unless interpreted", {
  p <- withr::local_tempfile(fileext = ".geojson")
  writeLines('{"type":"FeatureCollection","features":[{"type":"Feature",
    "geometry":{"type":"Polygon","coordinates":[[[0,0],[6,0],[6,6],[0,6],[0,0]]]},
    "properties":{"label":"a","layer":"l","level":1}}]}', p)
  expect_error(at_read_geojson(p), "Ambiguous legacy coordinate level")
  expect_identical(at_read_geojson(p, coordinate_level = 0L)$l$rois[[1]]$level, 0L)
  expect_identical(at_read_geojson(p, legacy_levels = "recorded")$l$rois[[1]]$level, 1L)
})
