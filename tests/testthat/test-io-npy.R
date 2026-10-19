# NumPy .npy integer-mask I/O: the interchange format for the HSI ground-truth
# masks (anatomy/state/uncertain/artefact) written by the Python annotator. The
# bridge must be lossless (bitfield codes survive) and faithful to numpy's
# C/Fortran order so a round trip and a Python consumer agree on every pixel.

# A minimal, independent C-order uint8 .npy writer, to check the reader without
# depending on the package's own writer (avoids a circular test).
write_npy_c_u1 <- function(m, path) {
  H <- nrow(m); W <- ncol(m)
  dict <- sprintf("{'descr': '|u1', 'fortran_order': False, 'shape': (%d, %d), }", H, W)
  total <- 10L + nchar(dict) + 1L
  pad <- (64L - (total %% 64L)) %% 64L
  dict <- paste0(dict, strrep(" ", pad), "\n")
  con <- file(path, "wb"); on.exit(close(con))
  writeBin(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 1, 0)), con)
  writeBin(as.integer(nchar(dict)), con, size = 2L, endian = "little")
  writeBin(charToRaw(dict), con)
  writeBin(as.integer(t(m)), con, size = 1L, endian = "little") # row-major
}

anat_mask <- function() {
  lyr <- at_layer("anatomy", labels = c("wound", "healthy"))
  lyr <- at_layer_add(lyr, at_roi_rect(1, 1, 5, 5, label = "wound"))
  lyr <- at_layer_add(lyr, at_roi_rect(6, 6, 9, 9, label = "healthy"))
  at_mask(lyr, type = "multiclass", values = c(wound = 1L, healthy = 3L),
          dims = c(10, 10))
}

test_that(".npy_read_matrix reads a C-order uint8 array faithfully", {
  m0 <- matrix(c(1, 2, 3, 4, 5, 6), nrow = 2, ncol = 3, byrow = TRUE)
  p <- tempfile(fileext = ".npy")
  write_npy_c_u1(m0, p)
  got <- .npy_read_matrix(p)
  expect_identical(dim(got), c(2L, 3L))
  expect_equal(got, matrix(c(1L, 2L, 3L, 4L, 5L, 6L), 2, 3, byrow = TRUE))
})

test_that("an annot_mask round-trips through .npy losslessly", {
  m <- anat_mask()
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p)
  m2 <- at_read_npy(p)
  expect_equal(as.matrix(m2), as.matrix(m))
  expect_identical(attr(m2, "dims"), attr(m, "dims"))
})

test_that("the sidecar legend recovers labels on read", {
  m <- anat_mask()
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p)
  lg <- at_mask_legend(at_read_npy(p))
  expect_identical(lg$label[lg$value == 1L], "wound")
  expect_identical(lg$label[lg$value == 3L], "healthy")
})

test_that("composite bitfield codes survive a round trip (not polygonised away)", {
  lyr <- at_layer("artefact", labels = c("specular", "blood"))
  lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 6, 6, label = "specular"))
  lyr <- at_layer_add(lyr, at_roi_rect(4, 4, 10, 10, label = "blood"))
  m <- at_mask(lyr, type = "multiclass", values = c(specular = 1L, blood = 2L),
               overlap = "bitor", dims = c(10, 10))
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p, dtype = "int32")
  expect_identical(.npy_read_matrix(p)[5, 5], 3L)
})

test_that("at_write_npy refuses to overwrite without overwrite = TRUE", {
  m <- anat_mask()
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p)
  expect_error(at_write_npy(m, p), "exists")
  expect_invisible(at_write_npy(m, p, overwrite = TRUE))
})

test_that("at_read_mask polygonises a .npy via the wired reader", {
  m <- anat_mask()
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p)
  lyr <- at_read_mask(p)
  expect_s3_class(lyr, "annot_layer")
  expect_true("wound" %in% vapply(lyr$rois, `[[`, character(1), "label"))
})

test_that("transpose reconciles native-order (x, y) files with hyperannotatR [y, x]", {
  lyr <- at_layer("a", labels = "a")
  lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 3, 4, label = "a"))
  m <- at_mask(lyr, type = "multiclass", values = c(a = 1L), dims = c(6, 4))
  expect_identical(dim(as.matrix(m)), c(4L, 6L)) # [y, x]
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p, transpose = TRUE) # writes numpy shape (width, height) = (6, 4)
  expect_identical(dim(.npy_read_matrix(p)), c(6L, 4L)) # faithful read is [x, y]
  back <- at_read_npy(p, transpose = TRUE) # brings it back to [y, x]
  expect_equal(as.matrix(back), as.matrix(m))
  expect_identical(attr(back, "dims"), attr(m, "dims"))
})

test_that("transpose brings a TIVITA (width, height) ground truth into [y, x] (integration)", {
  f <- file.path("..", "..", "hsi-workbench", "reference", "annotations",
                 "HSI-BVZ-001_2019_11_11_22_11_52", "anatomy.npy")
  skip_if(!file.exists(f), "no workbench reference annotation present")
  gt <- at_read_npy(f, transpose = TRUE)
  expect_identical(dim(as.matrix(gt)), c(480L, 640L)) # [y, x], matches the cube
})

test_that("reads a real Python-written ground-truth .npy (integration)", {
  f <- file.path("..", "..", "hsi-workbench", "reference", "annotations",
                 "HSI-BVZ-001_2019_11_11_22_11_52", "anatomy.npy")
  skip_if(!file.exists(f), "no workbench reference annotation present")
  m <- .npy_read_matrix(f)
  expect_identical(dim(m), c(640L, 480L)) # numpy shape (640, 480), native (x, y)
  expect_true(all(unique(as.integer(m)) %in% 0:5))
  expect_gt(sum(m == 1L), 0L) # some 'wound' pixels
})

# A hand-written .npy: any descr and shape, with an explicit raw payload.
write_npy_raw <- function(path, descr, shape, payload, fortran = FALSE, version = 1L) {
  dict <- sprintf("{'descr': '%s', 'fortran_order': %s, 'shape': (%s), }",
                  descr, if (fortran) "True" else "False", shape)
  pre <- if (version >= 2L) 12L else 10L
  pad <- (64L - ((pre + nchar(dict) + 1L) %% 64L)) %% 64L
  dict <- paste0(dict, strrep(" ", pad), "\n")
  con <- file(path, "wb")
  on.exit(close(con))
  writeBin(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, version, 0)), con)
  writeBin(as.integer(nchar(dict)), con, size = if (version >= 2L) 4L else 2L, endian = "little")
  writeBin(charToRaw(dict), con)
  writeBin(payload, con)
}

# Little-endian bytes of 32-bit words.
le32 <- function(v) writeBin(as.integer(v), raw(), size = 4L, endian = "little")

test_that("a short NPY payload is refused, never recycled (A13)", {
  f <- withr::local_tempfile(fileext = ".npy")
  write_npy_raw(f, "<i4", "2, 2", le32(1:2))
  err <- tryCatch(.npy_read_matrix(f), error = function(e) e)
  expect_s3_class(err, "at_io_error")
  expect_identical(err$code, "PAYLOAD_SHORT")
})

test_that("int64 values are exact when they fit 32 bits and refused otherwise", {
  f <- withr::local_tempfile(fileext = ".npy")
  # 2 x 2 C-order: 1, -2, 70000, 0 as (low, high) little-endian word pairs.
  write_npy_raw(f, "<i8", "2, 2", le32(c(1, 0, -2, -1, 70000, 0, 0, 0)))
  expect_identical(.npy_read_matrix(f), matrix(c(1L, 70000L, -2L, 0L), 2, 2))
  write_npy_raw(f, ">i8", "1, 2", c(writeBin(c(0L, 5L, -1L, -3L), raw(), size = 4L, endian = "big")))
  expect_identical(.npy_read_matrix(f), matrix(c(5L, -3L), 1, 2))
  write_npy_raw(f, "<i8", "1, 1", le32(c(1, 1))) # 2^32 + 1
  expect_identical(tryCatch(.npy_read_matrix(f), error = function(e) e$code), "VALUE_OUT_OF_RANGE")
})

test_that("unsigned 32/64-bit values beyond the integer range are refused, not negated", {
  f <- withr::local_tempfile(fileext = ".npy")
  write_npy_raw(f, "<u4", "1, 2", le32(c(7, -1))) # 7 and 2^32 - 1
  expect_identical(tryCatch(.npy_read_matrix(f), error = function(e) e$code), "VALUE_OUT_OF_RANGE")
  write_npy_raw(f, "<u4", "1, 2", le32(c(7, 9)))
  expect_identical(.npy_read_matrix(f), matrix(c(7L, 9L), 1, 2))
  write_npy_raw(f, "<u8", "1, 1", le32(c(-1, 0))) # 2^32 - 1
  expect_identical(tryCatch(.npy_read_matrix(f), error = function(e) e$code), "VALUE_OUT_OF_RANGE")
  write_npy_raw(f, "<u2", "1, 2", writeBin(c(65535L, 3L), raw(), size = 2L, endian = "little"))
  expect_identical(.npy_read_matrix(f), matrix(c(65535L, 3L), 1, 2))
})

test_that("malformed NPY headers and widths are refused with codes", {
  f <- withr::local_tempfile(fileext = ".npy")
  write_npy_raw(f, "<i3", "1, 1", as.raw(c(1, 0, 0)))
  expect_identical(tryCatch(.npy_read_matrix(f), error = function(e) e$code), "NPY_INVALID")
  write_npy_raw(f, "<i4", "1, 1", le32(4), version = 2L)
  expect_identical(.npy_read_matrix(f), matrix(4L, 1, 1))
  write_npy_raw(f, "<i4", "2, 3, 4", le32(1:24))
  expect_error(.npy_read_matrix(f), "2-D")
  write_npy_raw(f, "<f4", "1, 1", le32(0))
  expect_error(.npy_read_matrix(f), "integer")
})

test_that("C- and Fortran-order non-square arrays decode to the same matrix", {
  m <- matrix(1:6, 2, 3)
  fc <- withr::local_tempfile(fileext = ".npy")
  write_npy_raw(fc, "<i4", "2, 3", le32(t(m)))
  ff <- withr::local_tempfile(fileext = ".npy")
  write_npy_raw(ff, "<i4", "2, 3", le32(m), fortran = TRUE)
  expect_identical(.npy_read_matrix(fc), m)
  expect_identical(.npy_read_matrix(ff), m)
})

test_that("the NPY writer refuses values outside the dtype and missing values", {
  m <- .mask_recover(matrix(c(-1L, 0L, 1L, 2L), 2, 2))
  f <- withr::local_tempfile(fileext = ".npy")
  expect_error(at_write_npy(m, f, dtype = "uint8", legend = FALSE), "range")
  expect_false(file.exists(f))
  at_write_npy(m, f, dtype = "int16", legend = FALSE)
  expect_identical(.npy_read_matrix(f), matrix(c(-1L, 0L, 1L, 2L), 2, 2))
  m2 <- m
  m2[1, 1] <- NA_integer_
  expect_error(at_write_npy(m2, f, dtype = "int32", legend = FALSE, overwrite = TRUE),
               "finite|integer")
  expect_identical(.npy_read_matrix(f), matrix(c(-1L, 0L, 1L, 2L), 2, 2))
})
