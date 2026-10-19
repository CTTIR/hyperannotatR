test_that("all six backends are registered with availability flags", {
  bl <- at_backend_list()
  expect_s3_class(bl, "tbl_df")
  expect_setequal(bl$name, c("raster", "tiff", "ometiff", "cuvis", "tivita", "envi"))
  expect_identical(names(bl), c("name", "description", "extensions", "available", "metadata_only", "window_read"))
  expect_type(bl$available, "logical")
})

test_that("core backends are available; Bioc/vendor backends reflect installation", {
  bl <- at_backend_list()
  avail <- setNames(bl$available, bl$name)
  expect_true(avail[["raster"]])
  expect_true(avail[["envi"]])
  expect_identical(avail[["cuvis"]], nzchar(system.file(package = "cuvis.r")))
  expect_identical(avail[["ometiff"]], requireNamespace("RBioFormats", quietly = TRUE))
})

test_that("at_backend_get errors on unknown backends", {
  expect_error(at_backend_get("nope"), "No backend")
})

test_that("at_backend_detect picks the right backend by content/extension", {
  expect_identical(at_backend_detect(at_example_path("tissue")), "raster")
  expect_identical(at_backend_detect(at_example_path("cube")), "envi")
})

test_that("at_tile returns [y, x, band] arrays for every access pattern", {
  skip_if_not_installed("tiff")
  img <- at_example_image("multiplex")
  expect_identical(dim(at_tile(img)), c(512L, 512L, 4L))
  expect_identical(dim(at_tile(img, xrange = c(1, 16), yrange = c(1, 32))), c(32L, 16L, 4L))
  expect_identical(dim(at_tile(img, bands = 1L)), c(512L, 512L, 1L))
  expect_identical(dim(at_tile(img, bands = c(1L, 3L))), c(512L, 512L, 2L))
  expect_identical(dim(at_tile(img, level = 2L)), c(128L, 128L, 4L))
})

test_that("at_tile is always 3-dimensional even for single band", {
  skip_if_not_installed("tiff")
  img <- at_example_image("tissue")
  expect_length(dim(at_tile(img, bands = 1L)), 3L)
})

test_that("at_tile validates ranges, level, and bands", {
  skip_if_not_installed("tiff")
  img <- at_example_image("tissue")
  expect_error(at_tile(img, xrange = c(1, 9999)), "out of bounds")
  expect_error(at_tile(img, level = 5), "exceed")
  expect_error(at_tile(img, bands = 99), "out of range")
})

test_that("at_read_image errors informatively on unreadable/unknown files", {
  expect_error(at_read_image(tempfile()), "existing file")
  f <- withr::local_tempfile(fileext = ".xyz")
  writeLines("x", f)
  expect_error(at_read_image(f), "No backend recognises")
})

# ---- Read identity and the tile contract (audit A09, C1) -------------------

test_that("one relative name in two directories never shares cached pixels (A09)", {
  skip_if_not_installed("tiff")
  d1 <- withr::local_tempdir()
  d2 <- withr::local_tempdir()
  tiff::writeTIFF(matrix(0, 4, 4), file.path(d1, "same.tif"), bits.per.sample = 8L)
  tiff::writeTIFF(matrix(1, 4, 4), file.path(d2, "same.tif"), bits.per.sample = 8L)
  .tile_cache_clear()
  a <- withr::with_dir(d1, at_read_image("same.tif"))
  b <- withr::with_dir(d2, at_read_image("same.tif"))
  expect_identical(a$source, normalizePath(file.path(d1, "same.tif")))
  expect_false(identical(a$cache_identity, b$cache_identity))
  expect_identical(max(at_tile(a)), 0)
  expect_identical(max(at_tile(b)), 255)
})

test_that("a replaced file is re-read, not served from the cache", {
  skip_if_not_installed("tiff")
  f <- withr::local_tempfile(fileext = ".tif")
  tiff::writeTIFF(matrix(0, 4, 4), f, bits.per.sample = 8L)
  .tile_cache_clear()
  invisible(at_tile(at_read_image(f)))
  Sys.sleep(1.1) # file times have one-second resolution on some file systems
  tiff::writeTIFF(matrix(1, 4, 4), f, bits.per.sample = 8L)
  expect_identical(max(at_tile(at_read_image(f))), 255)
})

test_that("hand-built images with one source string are not cross-cached", {
  .tile_cache_clear()
  mk <- function(v) new_annot_image("same.tif", "raster", c(4L, 4L), 1L, list(c(4L, 4L)), 1L,
                                    handle = list(data = array(v, c(4, 4, 1))))
  invisible(at_tile(mk(0)))
  expect_identical(max(at_tile(mk(255))), 255)
})

test_that("at_tile refuses a missing handle or a wrong-shaped tile", {
  img <- tiny_image() # no handle, no file
  err <- tryCatch(at_tile(img), error = identity)
  expect_s3_class(err, "at_io_error")
  expect_identical(err$code, "IMAGE_UNAVAILABLE")
  at_backend_register("bad_shape", read_fn = function(path, ...) NULL,
                      tile_fn = function(img, level, xrange, yrange, bands) array(0, c(2, 2, 1)),
                      detect_fn = function(path) FALSE, available_fn = function() TRUE)
  withr::defer(rm("bad_shape", envir = .backend_registry))
  bad <- new_annot_image("x", "bad_shape", c(4L, 4L), 1L, list(c(4L, 4L)), 1L, handle = list())
  err <- tryCatch(at_tile(bad), error = identity)
  expect_identical(err$code, "BACKEND_CONTRACT")
})

test_that("reader options are recorded so a stripped image reopens alike", {
  expect_true(.serializable_options(list(wavelengths = 1:3, value_unit = "nm")))
  expect_false(.serializable_options(list(f = identity)))
  f <- withr::local_tempfile(fileext = ".png")
  writeLines("x", f)
  expect_error(at_read_image(f, backend = "raster", hook = identity),
               class = "at_validation_error")
  cube <- at_example_image("cube")
  d <- cube$source_descriptor
  expect_identical(d$backend, "envi")
  expect_identical(d$options, list())
  # An ENVI cube is recorded with both companion files, so a replaced header
  # or payload is detected on reopen.
  expect_setequal(names(d$files), c("header", "payload"))
  expect_identical(at_inspect_source(cube)$status, "available")
})
