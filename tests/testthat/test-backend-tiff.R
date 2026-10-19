skip_if_not_installed("tiff")

test_that("the multiplex example reads as a 3-level 4-channel pyramid", {
  img <- at_example_image("multiplex")
  expect_identical(at_dims(img, 0), c(512L, 512L))
  expect_identical(at_dims(img, 1), c(256L, 256L))
  expect_identical(at_dims(img, 2), c(128L, 128L))
  expect_identical(at_n_bands(img), 4L)
  expect_true(at_is_pyramidal(img))
})

test_that("multiplex band names are set by the example helper", {
  img <- at_example_image("multiplex")
  expect_identical(at_bands(img)$name, c("DAPI", "CD3", "CD8", "PanCK"))
})

test_that("tiff detection excludes OME/qptiff (handled by ometiff)", {
  expect_true(.tiff_detect("a.tif"))
  expect_true(.tiff_detect("a.tiff"))
  expect_false(.tiff_detect("a.ome.tif"))
  expect_false(.tiff_detect("a.qptiff"))
})

test_that("pyramid levels shrink in size", {
  img <- at_example_image("multiplex")
  d0 <- at_dims(img, 0)
  d2 <- at_dims(img, 2)
  expect_true(all(d2 < d0))
})

# Expected values below are the integer arrays the files were written from.

test_that("multi-sample TIFFs return their stored integers, like one-sample TIFFs", {
  # readTIFF(as.is = TRUE) rescales multi-sample pages to [0, 1]; hyperannotatR
  # must report the stored values its dtype describes for every channel count.
  dir <- withr::local_tempdir()
  for (bits in c(8L, 16L)) {
    mx <- 2^bits - 1
    for (ch in c(1L, 3L, 4L)) {
      a <- array((seq_len(3L * 5L * ch) * 7L) %% (mx + 1), c(3L, 5L, ch))
      f <- file.path(dir, sprintf("t%d_%d.tif", bits, ch))
      tiff::writeTIFF(if (ch == 1L) a[, , 1] / mx else a / mx, f, bits.per.sample = bits)
      img <- suppressWarnings(at_read_image(f))
      lbl <- paste(bits, "bit", ch, "channel")
      expect_identical(at_dims(img), c(5L, 3L), info = lbl)
      expect_identical(img$dtype, paste0("uint", bits), info = lbl)
      expect_identical(as.vector(suppressWarnings(at_tile(img))), as.vector(a), info = lbl)
    }
  }
})

test_that("the multiplex example holds whole 16-bit values", {
  tile <- at_tile(at_example_image("multiplex"), xrange = c(1, 64), yrange = c(1, 64))
  expect_true(all(tile == round(tile)))
  expect_true(max(tile) > 255 && max(tile) <= 65535)
})

test_that("equal-size pages are refused as ambiguous instead of keeping only one", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "stack.tif")
  pages <- lapply(1:3, function(k) matrix(k * 20 + 0:11, 3, 4))
  tiff::writeTIFF(lapply(pages, function(m) m / 255), f, bits.per.sample = 8L)
  err <- tryCatch(at_read_image(f), error = function(e) e)
  expect_identical(err$code, "TIFF_AMBIGUOUS")
  expect_match(conditionMessage(err), "Ambiguous TIFF directories")
  f2 <- file.path(dir, "mixed.tif")
  tiff::writeTIFF(list(matrix(0.5, 8, 8), array(0.2, c(4, 4, 3))), f2, bits.per.sample = 8L)
  expect_identical(tryCatch(at_read_image(f2), error = function(e) e$code), "TIFF_AMBIGUOUS")
})

test_that("a pyramid of multi-channel pages keeps every level and channel", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "pyr.tif")
  l0 <- array((seq_len(8 * 6 * 2) %% 200), c(8, 6, 2))
  l1 <- array((seq_len(4 * 3 * 2) %% 200), c(4, 3, 2))
  tiff::writeTIFF(list(l0 / 255, l1 / 255), f, bits.per.sample = 8L)
  img <- suppressWarnings(at_read_image(f))
  expect_identical(at_n_levels(img), 2L)
  expect_identical(at_dims(img, 1), c(3L, 4L))
  expect_identical(as.vector(suppressWarnings(at_tile(img, level = 1))), as.vector(l1))
})

test_that("planar-separate TIFFs are refused instead of decoded as zeros (A35)", {
  f <- withr::local_tempfile(fileext = ".tif")
  write_planar_tiff(f, planar_cube())
  expect_identical(attr(tiff::readTIFF(f, info = TRUE), "planar.config"), "separate")
  err <- tryCatch(at_read_image(f, backend = "tiff"), error = function(e) e)
  expect_identical(err$code, "TIFF_UNSUPPORTED")
  expect_match(conditionMessage(err), "Planar-separate")
})
