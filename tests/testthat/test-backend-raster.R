# The raster backend. Pixel expectations come from an independent decoder
# (png::readPNG) or from the integer arrays the fixtures were written from,
# never from hyperannotatR's own reader.

# `.raster_read()` as it behaves without magick installed.
raster_read_without_magick <- function() {
  reader <- .raster_read
  scope <- new.env(parent = environment(reader))
  scope$requireNamespace <- function(package, ...) {
    if (package == "magick") FALSE else base::requireNamespace(package, ...)
  }
  environment(reader) <- scope
  reader
}

# A non-square [height, width, channel] integer array with distinct values, so
# a width/height swap or a channel mix-up cannot pass unnoticed.
distinct_pixels <- function(h, w, ch, max = 255) {
  array((seq_len(h * w * ch) * 7L) %% (max + 1), c(h, w, ch))
}

test_that("the tissue example reads as a 512x512 RGB raster", {
  skip_if_not_installed("magick")
  img <- at_example_image("tissue")
  expect_s3_class(img, "annot_image")
  expect_identical(at_dims(img), c(512L, 512L))
  expect_identical(at_n_bands(img), 3L)
  expect_identical(at_n_levels(img), 1L)
  expect_false(at_is_pyramidal(img))
  expect_false(at_is_spectral(img))
})

test_that("raster tiles carry 0-255 intensities", {
  skip_if_not_installed("magick")
  img <- at_example_image("tissue")
  tile <- at_tile(img, xrange = c(1, 8), yrange = c(1, 8))
  expect_true(all(tile >= 0 & tile <= 255))
})

test_that("PNG pixels match an independent decoder exactly", {
  skip_if_not_installed("magick")
  skip_if_not_installed("png")
  p <- at_example_path("tissue")
  ref <- round(png::readPNG(p) * 255)
  tile <- at_tile(at_read_image(p))
  expect_identical(dim(tile), dim(ref))
  expect_identical(max(abs(tile - ref)), 0)
  # A pixel inside the magenta disc of the example.
  expect_identical(tile[200, 180, ], c(192, 95, 167))
})

test_that("grey, grey-alpha, RGB and RGBA PNGs decode in [y, x, band] order", {
  skip_if_not_installed("magick")
  skip_if_not_installed("png")
  dir <- withr::local_tempdir()
  for (ch in 1:4) {
    a <- distinct_pixels(3L, 5L, ch)
    f <- file.path(dir, sprintf("px%d.png", ch))
    png::writePNG(if (ch == 1L) a[, , 1] / 255 else a / 255, f)
    img <- at_read_image(f)
    expect_identical(at_dims(img), c(5L, 3L), info = ch)
    expect_identical(at_n_bands(img), ch, info = ch)
    expect_identical(img$dtype, "uint8", info = ch)
    expect_identical(as.vector(at_tile(img)), as.vector(a), info = ch)
  }
  expect_identical(at_bands(at_read_image(file.path(dir, "px2.png")))$name, c("Gray", "Alpha"))
})

test_that("without magick, planar-separate TIFFs are refused instead of decoded as zeros (A35)", {
  skip_if_not_installed("tiff")
  f <- withr::local_tempfile(fileext = ".tif")
  write_planar_tiff(f, planar_cube())
  err <- tryCatch(raster_read_without_magick()(f), error = function(e) e)
  expect_s3_class(err, "at_io_error")
  expect_identical(err$code, "TIFF_UNSUPPORTED")
})

test_that("without magick, TIFFs are display-converted to 0-255 and PNGs are refused", {
  skip_if_not_installed("tiff")
  skip_if_not_installed("png")
  reader <- raster_read_without_magick()
  dir <- withr::local_tempdir()
  rgb8 <- distinct_pixels(3L, 5L, 3L)
  f8 <- file.path(dir, "rgb8.tif")
  tiff::writeTIFF(rgb8 / 255, f8, bits.per.sample = 8L)
  img8 <- reader(f8)
  expect_identical(img8$dims, c(5L, 3L))
  expect_identical(img8$dtype, "uint8")
  expect_identical(img8$meta$sample_contract, "display-converted-0-255")
  expect_equal(as.vector(img8$handle$data), as.vector(rgb8), tolerance = 1e-9)
  grey16 <- matrix(as.double((seq_len(15) * 3001L) %% 65536L), 3, 5)
  f16 <- file.path(dir, "grey16.tif")
  tiff::writeTIFF(grey16 / 65535, f16, bits.per.sample = 16L)
  img16 <- reader(f16)
  expect_equal(as.vector(img16$handle$data), as.vector(grey16) / 65535 * 255, tolerance = 1e-9)
  fp <- file.path(dir, "x.png")
  png::writePNG(rgb8 / 255, fp)
  err <- tryCatch(reader(fp), error = function(e) e)
  expect_s3_class(err, "at_capability_error")
  expect_identical(err$code, "CAPABILITY_UNAVAILABLE")
  expect_match(conditionMessage(err), "magick")
})

test_that("raster detection matches image extensions", {
  expect_true(.raster_detect("a.png"))
  expect_true(.raster_detect("a.JPG"))
  expect_false(.raster_detect("a.cu3"))
})
