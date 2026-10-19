test_that("QuPath colorRGB encodes as a signed 32-bit int (negative case)", {
  expect_identical(.hex_to_signed_int("#FFFFFF"), -1L)
  expect_true(.hex_to_signed_int("#E69F00") < 0L)
  # round-trips
  for (h in c("#E69F00", "#56B4E9", "#000000", "#FFFFFF", "#5E2C8E")) {
    expect_identical(toupper(.signed_int_to_hex(.hex_to_signed_int(h))), toupper(h))
  }
})

test_that("QuPath round-trip preserves classification names and colours", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_qupath(proj, p)
  lyr <- at_read_qupath(p)
  expect_setequal(unique(vapply(lyr$rois, `[[`, character(1), "label")),
                  c("tissue", "tumour"))
  # A recovered colour maps back to a valid hex.
  expect_true(all(grepl("^#[0-9A-Fa-f]{6}$", lyr$style$colour)))
})

test_that("QuPath reader handles null classification", {
  p <- withr::local_tempfile(fileext = ".geojson")
  fc <- list(type = "FeatureCollection", features = list(list(
    type = "Feature", id = "x",
    geometry = list(type = "Polygon",
                    coordinates = list(list(c(0, 0), c(5, 0), c(5, 5), c(0, 5), c(0, 0)))),
    properties = list(classification = NULL, object_type = "annotation")
  )))
  jsonlite::write_json(fc, p, auto_unbox = TRUE, null = "null")
  lyr <- at_read_qupath(p)
  expect_identical(lyr$rois[[1]]$label, "unclassified")
})

test_that("QuPath detections map object_type through", {
  lyr <- at_layer_add(at_layer("l"),
                      at_roi_rect(0, 0, 5, 5, label = "cell", source = "mask"))
  proj <- at_project(small_image(), lyr)
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_qupath(proj, p)
  fc <- jsonlite::read_json(p, simplifyVector = FALSE)
  expect_identical(fc$features[[1]]$properties$objectType, "detection")
  p2 <- withr::local_tempfile(fileext = ".geojson")
  at_write_qupath(proj, p2, dialect = "legacy")
  fc2 <- jsonlite::read_json(p2, simplifyVector = FALSE)
  expect_identical(fc2$features[[1]]$properties$object_type, "detection")
})

test_that("QuPath records the written coordinate level and reads it back (A06)", {
  img <- new_annot_image("pyr.tif", "raster", c(64L, 64L), 2L,
                         list(c(64L, 64L), c(32L, 32L)), 1L)
  proj <- at_project(img, at_layer_add(at_layer("l"), at_roi_rect(0, 0, 3, 3, label = "a", level = 1L)))
  for (dialect in c("qupath", "legacy")) for (lv in 0:1) {
    p <- withr::local_tempfile(fileext = ".geojson")
    at_write_qupath(proj, p, level = lv, dialect = dialect)
    props <- jsonlite::read_json(p)$features[[1]]$properties
    lbl <- paste(dialect, lv)
    expect_identical(props$level, lv, info = lbl)
    expect_identical(props$source_level, 1L, info = lbl)
    expect_identical(props$coordinate_schema, "annotatR-pixel-level-v1", info = lbl)
    if (dialect == "qupath") {
      expect_identical(props$metadata$annotatr_coordinate_level, as.character(lv), info = lbl)
      expect_identical(props$metadata$annotatr_coordinate_schema, "annotatR-pixel-level-v1", info = lbl)
      expect_identical(props$metadata$annotatr_level, "1", info = lbl)
    }
    back <- at_read_qupath(p)
    expect_identical(back$rois[[1]]$level, lv, info = lbl)
    # 6 x 6 level-0 pixels whichever level the file was written at.
    expect_identical(at_rois(at_project(img, back))$area_px, 36, info = lbl)
  }
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_qupath(proj, p, level = 1L)
  expect_identical(at_read_qupath(p, coordinate_level = 0L)$rois[[1]]$level, 0L)
})

test_that("only metadata survives QuPath's own round trip, and it still carries the level", {
  img <- new_annot_image("pyr.tif", "raster", c(64L, 64L), 2L,
                         list(c(64L, 64L), c(32L, 32L)), 1L)
  proj <- at_project(img, at_layer_add(at_layer("l"), at_roi_rect(0, 0, 3, 3, label = "a", level = 1L)))
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_qupath(proj, p, level = 1L)
  fc <- jsonlite::read_json(p)
  keep <- c("objectType", "classification", "isLocked", "metadata")
  fc$features[[1]]$properties <- fc$features[[1]]$properties[intersect(keep, names(fc$features[[1]]$properties))]
  jsonlite::write_json(fc, p, auto_unbox = TRUE, null = "null", digits = NA)
  expect_identical(at_read_qupath(p)$rois[[1]]$level, 1L)
})

test_that("hyperannotatR 0.2.0 QuPath files keep reading at level 0", {
  # hyperannotatR 0.2.0 stored the ROI's own level in annotatr_level, not the level
  # of the written coordinates, so it is not trusted.
  p <- withr::local_tempfile(fileext = ".geojson")
  writeLines('{"type":"FeatureCollection","features":[{"type":"Feature","id":"x",
    "geometry":{"type":"Polygon","coordinates":[[[0,0],[6,0],[6,6],[0,6],[0,0]]]},
    "properties":{"objectType":"annotation","metadata":{"annotatr_roi_id":"r1","annotatr_level":"1"}}}]}', p)
  expect_identical(at_read_qupath(p)$rois[[1]]$level, 0L)
  expect_identical(at_read_qupath(test_path("fixtures", "qupath-0.7.0",
                                            "qupath_roundtrip_annotatr020.geojson"))$rois[[1]]$level, 0L)
})

test_that("a label with different layer colours is written with one colour and reads back", {
  a <- at_layer_add(at_layer("a", labels = "t", style = at_style(colour = c(t = "#FF0000"))),
                    at_roi_rect(0, 0, 2, 2, label = "t"))
  b <- at_layer_add(at_layer("b", labels = "t", style = at_style(colour = c(t = "#0000FF"))),
                    at_roi_rect(4, 4, 6, 6, label = "t"))
  proj <- at_add_layer(at_project(small_image(), a), b)
  for (dialect in c("qupath", "legacy")) {
    p <- withr::local_tempfile(fileext = ".geojson")
    at_write_qupath(proj, p, dialect = dialect)
    lyr <- at_read_qupath(p)
    expect_identical(at_layer_n(lyr), 2L, info = dialect)
    expect_identical(toupper(lyr$style$colour[["t"]]), "#FF0000", info = dialect)
  }
})

test_that("unsigned colorRGB values and pre-0.4 measurement arrays are read", {
  p <- withr::local_tempfile(fileext = ".geojson")
  writeLines('{"type":"FeatureCollection","features":[{"type":"Feature","id":"x",
    "geometry":{"type":"Point","coordinates":[1,1]},
    "properties":{"object_type":"annotation",
      "classification":{"name":"Tumor","colorRGB":4294901760},
      "measurements":[{"name":"Area","value":12.5},{"name":"Mean","value":"NaN"}]}}]}', p)
  lyr <- at_read_qupath(p)
  expect_identical(toupper(lyr$style$colour[["Tumor"]]), "#FF0000")
  ms <- lyr$rois[[1]]$attributes$qupath$measurements
  expect_identical(ms$name, c("Area", "Mean"))
  expect_identical(ms$value_state, c("finite", "nan"))
  expect_identical(ms$value[1], 12.5)
})
