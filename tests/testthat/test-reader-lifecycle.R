test_that("closed image cache hits avoid rereads and retain public accounting", {
  d <- withr::local_tempdir()
  hdr <- file.path(d, "small.hdr")
  dat <- file.path(d, "small.dat")
  writeLines(c("ENVI", "samples = 3", "lines = 2", "bands = 2",
    "data type = 4", "interleave = bsq", "byte order = 0"), hdr)
  con <- file(dat, "wb")
  for (b in 1:2) for (y in 1:2) for (x in 1:3) {
    writeBin(as.double(100 * b + 10 * y + x), con, size = 4, endian = "little")
  }
  close(con)
  img <- at_close_image(at_read_image(hdr))
  .tile_cache_clear()
  .read_telemetry_reset()
  at_read_stats(img, reset = TRUE)
  first <- at_tile(img, xrange = c(1, 2), yrange = c(1, 2), bands = 2)
  expect_identical(as.numeric(first), c(211, 221, 212, 222))
  expect_identical(.read_telemetry()$binary_bytes, file.info(hdr)$size + 16)
  counts <- .read_telemetry()
  second <- at_tile(img, xrange = c(1, 2), yrange = c(1, 2), bands = 2)
  expect_identical(second, first)
  expect_identical(.read_telemetry(), counts)
  expect_identical(at_read_stats(img)[c("tiles", "file_bytes", "decoded_bytes", "max_tile_bytes")],
    list(tiles = 1L, file_bytes = 16, decoded_bytes = 32, max_tile_bytes = 32))
  # Another window counts as one more read; closing again creates a new
  # runtime identity and cannot inherit cached tiles or counters.
  expect_identical(at_tile(img, xrange = c(3, 3), yrange = c(2, 2), bands = 1)[1, 1, 1], 123)
  expect_identical(at_read_stats(img)$tiles, 2L)
  expect_identical(at_read_stats(img)$file_bytes, 20)
  expect_identical(at_read_stats(img)$decoded_bytes, 40)
  reclosed <- at_close_image(img)
  expect_identical(at_read_stats(reclosed)$tiles, 0L)
  invisible(at_tile(reclosed, xrange = c(1, 2), yrange = c(1, 2), bands = 2))
  expect_identical(at_read_stats(reclosed)$tiles, 1L)
  expect_identical(at_read_stats(img)$tiles, 2L)
  # A cached result must never mask a changed companion payload.
  Sys.setFileTime(dat, file.info(dat)$mtime + 2)
  err <- tryCatch(at_tile(img, xrange = c(1, 2), yrange = c(1, 2), bands = 2), error = identity)
  expect_s3_class(err, "at_io_error")
  expect_identical(err$code, "IMAGE_CHANGED")
  expect_identical(at_read_stats(img)$tiles, 2L)
})
