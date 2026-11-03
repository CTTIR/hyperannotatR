selection_fixture <- function(dir) {
  hdr <- file.path(dir, "small.hdr")
  dat <- file.path(dir, "small.dat")
  writeLines(c("ENVI", "samples = 2", "lines = 1", "bands = 1",
    "data type = 4", "interleave = bsq", "byte order = 0"), hdr)
  writeBin(c(11, 22), dat, size = 4, endian = "little")
  list(hdr = hdr, dat = dat)
}

test_that("ENVI discovery cannot replace a recorded payload with a new preferred file", {
  for (backend in c("envi", "tivita")) {
    f <- selection_fixture(withr::local_tempdir())
    img <- at_read_image(f$hdr, backend = backend)
    expect_identical(as.numeric(at_tile(img)), c(11, 22))
    saved <- tempfile(fileext = ".rds")
    withr::defer(unlink(saved))
    at_save_project(at_project(img), saved)
    writeBin(c(99, 88), sub("[.]dat$", "", f$dat), size = 4, endian = "little")
    expect_identical(at_inspect_source(img)$status, "changed")
    err <- tryCatch(at_tile(at_close_image(img)), error = identity)
    expect_identical(if (inherits(err, "error")) err$code else NULL, "IMAGE_CHANGED")
    restored <- at_load_project(saved)
    expect_null(restored$image$handle)
    expect_identical(at_inspect_source(restored)$status, "changed")
  }
})

test_that("ENVI discovery cannot replace a recorded header with a new preferred file", {
  f <- selection_fixture(withr::local_tempdir())
  img <- at_read_image(f$dat, backend = "envi")
  before <- at_tile(img)
  # This suffix takes precedence over the former small.hdr for a .dat input.
  writeLines(sub("byte order = 0", "byte order = 1", readLines(f$hdr)), paste0(f$dat, ".hdr"))
  expect_identical(at_inspect_source(img)$status, "changed")
  err <- tryCatch(at_tile(img), error = identity)
  expect_identical(if (inherits(err, "error")) err$code else NULL, "IMAGE_CHANGED")
  err <- tryCatch(at_tile(at_close_image(img)), error = identity)
  expect_identical(if (inherits(err, "error")) err$code else NULL, "IMAGE_CHANGED")
})

test_that("ENVI sibling symlink retargets invalidate cached and closed images", {
  root <- withr::local_tempdir()
  f <- selection_fixture(root)
  original <- file.path(root, "original.bin")
  replacement <- file.path(root, "replacement.bin")
  expect_true(file.rename(f$dat, original))
  if (!isTRUE(suppressWarnings(portable_test_link(original, f$dat)))) {
    skip("Host cannot create symbolic links")
  }
  writeBin(c(99, 88), replacement, size = 4, endian = "little")
  img <- at_read_image(f$hdr)
  expect_identical(as.numeric(at_tile(img)), c(11, 22))
  fs::link_delete(f$dat)
  expect_true(portable_test_link(replacement, f$dat))
  expect_true(file.exists(original))
  expect_identical(at_inspect_source(img)$status, "changed")
  err <- tryCatch(at_tile(img), error = identity)
  expect_identical(if (inherits(err, "error")) err$code else NULL, "IMAGE_CHANGED")
  err <- tryCatch(at_tile(at_close_image(img)), error = identity)
  expect_identical(if (inherits(err, "error")) err$code else NULL, "IMAGE_CHANGED")
})

test_that("a new ENVI header cannot change a recorded bare TIVITA interpretation", {
  root <- withr::local_tempdir()
  dat <- file.path(root, "tiny_SpecCube.dat")
  writeBin(c(11, 22), dat, size = 4, endian = "big")
  profile <- at_tivita_profile("tiny", width = 1, height = 1, bands = 2,
    header_values = 0, wavelengths = c(500, 600), value_unit = "raw")
  img <- at_read_image(dat, profile = profile)
  expect_identical(as.numeric(at_tile(img)), c(11, 22))
  writeLines(c("ENVI", "samples = 1", "lines = 1", "bands = 2",
    "data type = 4", "interleave = bsq", "byte order = 0",
    "wavelength = {500, 600}", "wavelength units = nm"), paste0(dat, ".hdr"))
  expect_identical(at_inspect_source(img)$status, "changed")
  err <- tryCatch(at_tile(at_close_image(img)), error = identity)
  expect_identical(if (inherits(err, "error")) err$code else NULL, "IMAGE_CHANGED")
})
