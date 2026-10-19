# helper local to this file
geom_type <- function(roi) as.character(sf::st_geometry_type(roi$geometry))

test_that("constructors produce the expected geometry types", {
  expect_identical(geom_type(at_roi_point(1, 2, label = "a")), "POINT")
  expect_identical(geom_type(at_roi_rect(0, 0, 4, 4, label = "a")), "POLYGON")
  expect_identical(geom_type(at_roi_circle(5, 5, 2, label = "a")), "POLYGON")
  expect_identical(geom_type(at_roi_ellipse(5, 5, 3, 2, label = "a")), "POLYGON")
  sq <- matrix(c(0, 0, 4, 0, 4, 4, 0, 4), ncol = 2, byrow = TRUE)
  expect_identical(geom_type(at_roi_polygon(sq, label = "a")), "POLYGON")
  expect_identical(
    geom_type(at_roi_freehand(cbind(c(0, 4, 2), c(0, 0, 4)), label = "a")),
    "POLYGON"
  )
})

test_that("rect validates ordering of bounds", {
  expect_error(at_roi_rect(4, 0, 0, 4, label = "a"), "xmax")
  expect_error(at_roi_rect(0, 4, 4, 0, label = "a"), "ymax")
})

test_that("area is correct and NA for non-areal geometry", {
  expect_equal(at_roi_area(at_roi_rect(0, 0, 10, 5, label = "a")), 50)
  expect_true(is.na(at_roi_area(at_roi_point(1, 1, label = "a"))))
  expect_equal(at_roi_area(donut_roi()), 100 - 16)
})

test_that("centroid and bbox are correct", {
  r <- at_roi_rect(0, 0, 10, 10, label = "a")
  expect_equal(at_roi_centroid(r), c(5, 5))
  expect_equal(at_roi_bbox(r), c(0, 0, 10, 10))
})

test_that("at_roi_rescale round-trips exactly", {
  r <- at_roi_rect(0, 0, 100, 100, label = "a")
  back <- at_roi_rescale(at_roi_rescale(r, 0, 2), 2, 0)
  expect_equal(
    sf::st_coordinates(r$geometry),
    sf::st_coordinates(back$geometry),
    tolerance = 1e-9
  )
  expect_identical(back$level, 0L)
})

test_that("rescale changes coordinates by the expected power-of-two factor", {
  r <- at_roi_point(100, 80, label = "a")
  r2 <- at_roi_rescale(r, 0, 2)
  co <- as.numeric(sf::st_coordinates(r2$geometry))
  expect_equal(co, c(25, 20))
  expect_identical(r2$level, 2L)
})

test_that("rescale does not modify its input (immutability)", {
  r <- at_roi_rect(0, 0, 100, 100, label = "a")
  snapshot <- r
  invisible(at_roi_rescale(r, 0, 2))
  expect_identical(r, snapshot)
})

test_that("buffer and simplify return annot_roi", {
  r <- at_roi_point(10, 10, label = "a")
  b <- at_roi_buffer(r, 5)
  expect_s3_class(b, "annot_roi")
  expect_gt(at_roi_area(b), 0)
  s <- at_roi_simplify(at_roi_circle(50, 50, 10, n_seg = 128, label = "a"), 1)
  expect_s3_class(s, "annot_roi")
})

test_that("invalid geometry is repaired with a warning", {
  bow <- matrix(c(0, 0, 10, 10, 10, 0, 0, 10, 0, 0), ncol = 2, byrow = TRUE)
  expect_warning(at_roi_polygon(bow, label = "bow"), "Repaired")
})

test_that("dots set reserved fields and store attributes", {
  r <- at_roi_point(1, 1, label = "a", source = "imported", grade = 3)
  expect_identical(r$source, "imported")
  expect_identical(r$attributes$grade, 3)
})

test_that("st_as_sf and st_geometry methods work", {
  r <- at_roi_rect(0, 0, 4, 4, label = "a")
  expect_s3_class(sf::st_as_sf(r), "sf")
  expect_s3_class(sf::st_geometry(r), "sfc")
})

test_that("plot returns a ggplot without drawing", {
  p <- plot(at_roi_rect(0, 0, 4, 4, label = "a"))
  expect_s3_class(p, "ggplot")
})

test_that("print and format produce output", {
  expect_output(print(at_roi_rect(0, 0, 4, 4, label = "a")), "annot_roi")
})

test_that("at_roi_polygon accepts holes and rejects bad coords", {
  outer <- matrix(c(0, 0, 10, 0, 10, 10, 0, 10), ncol = 2, byrow = TRUE)
  inner <- matrix(c(3, 3, 3, 7, 7, 7, 7, 3), ncol = 2, byrow = TRUE)
  r <- at_roi_polygon(outer, label = "a", hole = inner)
  expect_equal(at_roi_area(r), 100 - 16)
  expect_error(at_roi_polygon("nope", label = "a"), "numeric matrix")
})

test_that("at_roi_freehand rejects malformed input", {
  expect_error(at_roi_freehand(matrix(1:4, ncol = 2), label = "a"), "at least 3 rows")
})

test_that("physical area uses the pixel_size attribute or errors", {
  r <- at_roi_rect(0, 0, 10, 10, label = "a", pixel_size = c(2, 3))
  expect_equal(at_roi_area(r, units = "physical"), 100 * 6)
  r2 <- at_roi_rect(0, 0, 10, 10, label = "a")
  expect_error(at_roi_area(r2, units = "physical"), "pixel_size")
})

test_that("at_roi_simplify with a tolerance reduces vertices", {
  r <- at_roi_simplify(at_roi_circle(50, 50, 20, n_seg = 128, label = "a"), tolerance = 2)
  expect_s3_class(r, "annot_roi")
  expect_lt(nrow(sf::st_coordinates(r$geometry)), 129)
})

test_that("roi plot and sf coercions work", {
  r <- at_roi_rect(0, 0, 4, 4, label = "a")
  expect_s3_class(plot(r), "ggplot")
  expect_s3_class(sf::st_as_sf(r), "sf")
  expect_s3_class(sf::st_geometry(r), "sfc")
})

# ---- Measurements and validation (audit C5, C6, C9, C10, C13, C15) ---------

test_that("at_roi_area uses the real pyramid when an image is supplied (C5)", {
  img <- new_annot_image("a.tif", "tiff", c(100L, 80L), 2L,
                         list(c(100L, 80L), c(25L, 40L)), 1L)
  r <- at_roi_rect(0, 0, 5, 5, label = "a", level = 1)
  rt <- at_rois(at_project(img, at_layer_add(at_layer("l"), r)))
  expect_equal(at_roi_area(r, image = img), rt$area_px)   # 5*4 x 5*2 = 200
  expect_equal(at_roi_area(r, image = img), 200)
  expect_equal(at_roi_area(r, level = 1, image = img), 25)
})

test_that("physical area needs a two-value calibration and ignores the reporting level (C6)", {
  # A scalar pixel size used to give prod(0.5) = 0.5 instead of 0.25 per pixel;
  # calibrations are now two explicit values.
  expect_error(at_roi_area(at_roi_rect(0, 0, 10, 10, label = "a", pixel_size = 0.5),
                           units = "physical"), "two finite positive")
  r <- at_roi_rect(0, 0, 10, 10, label = "a", pixel_size = c(1, 2))
  expect_equal(at_roi_area(r, units = "physical"), 200)
  img <- small_image() # 0.5 x 0.5 um pixels, three pyramid levels
  plain <- at_roi_rect(0, 0, 10, 10, label = "a")
  expect_equal(at_roi_area(plain, units = "physical", image = img), 25)
  expect_equal(at_roi_area(plain, level = 1, units = "physical", image = img), 25)
  bad <- at_roi_rect(0, 0, 1, 1, label = "a", pixel_size = c(-1, 1))
  expect_error(at_roi_area(bad, units = "physical"), "two finite positive")
})

test_that("rescaling refuses a from_level other than the ROI's level (C9)", {
  im <- new_annot_image("a.tif", "tiff", c(100L, 100L), 2L,
                        list(c(100L, 100L), c(50L, 50L)), 1L)
  r <- at_roi_rect(0, 0, 10, 10, label = "a", level = 1)
  expect_error(at_transform(r, 0, 1, im), "must equal the ROI's level")
  expect_error(at_roi_rescale(r, 0, 2), "must equal the ROI's level")
  expect_equal(at_roi_area(at_transform(r, to_level = 0, img = im)), 400)
  expect_equal(at_roi_rescale(r, to_level = 0)$level, 0L)
})

test_that("a nearly closed ring is closed exactly (C10)", {
  m <- rbind(c(1e5, 5e4), c(1.001e5, 5e4), c(1.001e5, 5.01e4), c(1e5 + 1e-3, 5e4))
  r <- suppressWarnings(at_roi_polygon(m, label = "a"))
  ring <- r$geometry[[1]][[1]]
  expect_identical(ring[1, ], ring[nrow(ring), ])
})

test_that("constructors validate reserved fields, dots and coordinates (C13)", {
  expect_error(at_roi_point(1, 1, label = "a", id = NA), class = "at_validation_error")
  expect_error(at_roi_point(1, 1, label = "a", id = c("x", "y")), class = "at_validation_error")
  expect_error(at_roi_point(1, 1, label = "a", author = 3), class = "at_validation_error")
  expect_error(at_roi_point(1, 1, "a", 0L, "stray"), "must be named")
  expect_error(at_roi_polygon(rbind(c(0, 0), c(1, NA), c(1, 1)), label = "a"), "non-finite")
  expect_error(at_roi_polygon(matrix(as.character(1:6), 3), label = "a"), "numeric")
  expect_error(at_roi_polygon(cbind(1:3, 1:3, 1:3), label = "a"), "two-column")
  expect_error(at_roi_polygon(rbind(c(0, 0), c(1, 1), c(0, 0)), label = "a"), "3 distinct")
  expect_error(at_roi_freehand(rbind(c(0, 0), c(1, Inf), c(1, 1)), label = "a"), "non-finite")
})

test_that("buffering and simplifying drop shape-specific attributes (C15)", {
  r <- at_roi_circle(10, 10, 3, label = "a", locked = TRUE)
  r$attributes$qupath <- list(object_id = "u1", nucleus_geometry = list(), roi_native = "ellipse")
  b <- at_roi_buffer(r, 2)
  expect_null(b$attributes$shape)
  expect_null(b$attributes$qupath$nucleus_geometry)
  expect_null(b$attributes$qupath$roi_native)
  # Same object: identity and lock are kept.
  expect_identical(b$attributes$qupath$object_id, "u1")
  expect_true(b$attributes$locked)
  expect_null(at_roi_simplify(r, 0.5)$attributes$shape)
})
