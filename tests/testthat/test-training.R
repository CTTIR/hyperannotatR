skip_if_not_installed("tiff")

# A 40 x 30 image with known rectangles; masks are derived independently from
# pixel-centre membership of the rectangle bounds.
train_image <- function(name) {
  new_annot_image(source = paste0(name, ".tif"), backend = "raster", dims = c(40L, 30L),
                  n_levels = 1L, level_dims = list(c(40L, 30L)), n_bands = 3L,
                  handle = list(data = array(1, dim = c(30, 40, 3))))
}

train_session <- function(n = 4L) {
  s <- demo_session(n)
  for (i in seq_len(n)) {
    lyr <- at_layer("tissue", labels = c("tumour", "stroma"))
    lyr <- at_layer_add(lyr, at_roi_rect(2, 3, 12, 9, label = "tumour", id = sprintf("t-%d", i)))
    lyr <- at_layer_add(lyr, at_roi_rect(22, 2, 30, 18, label = "stroma", id = sprintf("s-%d", i)))
    s$projects[[i]] <- at_project(train_image(sprintf("img%d", i)), lyr, name = sprintf("img%d", i))
  }
  s
}

rect_membership <- function(xmin, ymin, xmax, ymax, w, h) {
  m <- matrix(FALSE, h, w)
  for (i in seq_len(h)) for (j in seq_len(w)) {
    m[i, j] <- (j - 0.5) >= xmin && (j - 0.5) < xmax && (i - 0.5) >= ymin && (i - 0.5) < ymax
  }
  m
}

test_that("grouped splits are deterministic, independent of RNG, and leak-free", {
  sess <- train_session(4)
  groups <- data.frame(entry_id = sprintf("entry-%04d", 1:4), sample_id = c("s1", "s1", "s2", "s3"))
  dest <- file.path(withr::local_tempdir(), "ds")
  ds <- at_training_export(sess, dest, tile_size = 10, group_by = "sample_id", groups = groups,
                           fractions = c(train = 0.34, validation = 0.33, test = 0.33), seed = 7)
  # Independent assignment: rank groups by sha256("7:<group>") and cut 3 groups into thirds.
  g <- c("s1", "s2", "s3")
  ranked <- g[order(vapply(g, function(x) unname(tools::sha256sum(bytes = charToRaw(paste0("7:", x)))),
                           character(1)), method = "radix")]
  expected <- stats::setNames(c("train", "validation", "test"), ranked)
  split_of <- vapply(ds$manifest$images, `[[`, character(1), "split")
  expect_identical(split_of, unname(expected[c("s1", "s1", "s2", "s3")]))
  expect_identical(ds$checks$status[ds$checks$check == "split_leakage"], "ok")
  set.seed(1); a <- .assign_splits(g, c(train = 1, test = 1), 3)
  set.seed(999); b <- .assign_splits(g, c(train = 1, test = 1), 3)
  expect_identical(a, b)
  err <- tryCatch(at_training_export(sess, file.path(withr::local_tempdir(), "x"),
                                     split = list(train = c("img1", "img2"), test = c("img2")),
                                     group_by = "image_id",
                                     groups = data.frame(entry_id = sprintf("entry-%04d", 1:4),
                                                         image_id = paste0("img", 1:4))),
                  error = function(e) e)
  expect_true(err$code %in% c("SPLIT_LEAKAGE", "GROUP_MISSING"))
})

test_that("tile grid, exclusions and mask values match independent arithmetic", {
  sess <- train_session(1)
  dest <- file.path(withr::local_tempdir(), "ds")
  ds <- at_training_export(sess, dest, tile_size = 16, overlap = 4, mask_type = "labelled",
                           label_map = c(tumour = 3L, stroma = 5L), fractions = c(train = 1))
  # Stride 12: x0 in 0, 12, 24, 36 (w = 40); y0 in 0, 12, 24 (h = 30). Full tiles need
  # x0 + 16 <= 40 and y0 + 16 <= 30: x0 in {0, 12, 24}, y0 in {0, 12}.
  tiles <- ds$manifest$tiles
  expect_identical(length(tiles), 4L * 3L)
  inc <- Filter(function(t) t$status == "included", tiles)
  expect_identical(length(inc), 6L)
  expect_identical(ds$manifest$counts$excluded$partial, 6L)
  full <- matrix(0L, 30, 40)
  full[rect_membership(2, 3, 12, 9, 40, 30)] <- 3L
  full[rect_membership(22, 2, 30, 18, 40, 30)] <- 5L
  for (t in inc) {
    m <- tiff::readTIFF(file.path(dest, t$mask_file), as.is = TRUE)
    expect_identical(matrix(as.integer(m), 16),
                     full[(t$y + 1):(t$y + 16), (t$x + 1):(t$x + 16)], label = t$tile_id)
  }
  expect_true(all(ds$checks$status == "ok"))
  lg <- ds$manifest$mask_encoding$class_legend
  expect_identical(vapply(lg, `[[`, integer(1), "code"), c(3L, 5L))
  expect_identical(ds$manifest$mask_encoding$annotatr_mask_type, "multiclass")
  # The 10 x 6 px tumour rectangle lies inside exactly one included tile.
  expect_equal(ds$manifest$counts$class_balance$train[["3"]], sum(full == 3L))
})

test_that("instance masks carry their own legend and images are written only on request", {
  sess <- train_session(1)
  dest <- file.path(withr::local_tempdir(), "ds")
  ds <- at_training_export(sess, dest, tile_size = 20, mask_type = "instance", include_images = TRUE,
                           bands = 2:3, fractions = c(train = 1))
  inst <- ds$manifest$images[[1]]$instance_legend
  expect_identical(vapply(inst, `[[`, character(1), "roi_id"), c("t-1", "s-1"))
  t1 <- Filter(function(t) t$status == "included", ds$manifest$tiles)[[1]]
  con <- file(file.path(dest, t1$image_file), "rb")
  magic <- readBin(con, "raw", 6)
  ver <- readBin(con, "raw", 2)
  hlen <- readBin(con, "integer", size = 2, signed = FALSE, endian = "little")
  header <- rawToChar(readBin(con, "raw", hlen))
  close(con)
  expect_identical(as.integer(magic[2:6]), as.integer(charToRaw("NUMPY")))
  expect_match(header, "'descr': '<f4'")
  expect_match(header, "'shape': \\(20, 20, 2\\)")
})

test_that("the dataset check detects tampered, out-of-range and leaking datasets", {
  sess <- train_session(2)
  dest <- file.path(withr::local_tempdir(), "ds")
  ds <- at_training_export(sess, dest, tile_size = 10, fractions = c(train = 0.5, test = 0.5))
  expect_true(all(at_training_check(dest, x = sess)$status == "ok"))
  t1 <- Filter(function(t) t$status == "included" && t$foreground_px > 0, ds$manifest$tiles)[[1]]
  m <- matrix(9L, 10, 10)
  tiff::writeTIFF(m / 255, file.path(dest, t1$mask_file), bits.per.sample = 8L)
  chk <- at_training_check(dest, x = sess)
  expect_identical(chk$status[chk$check == "integrity"], "fail")
  expect_identical(chk$status[chk$check == "label_range"], "fail")
  expect_identical(chk$status[chk$check == "source_agreement"], "fail")
  man <- jsonlite::read_json(file.path(dest, "training-manifest.json"))
  man$tiles[[1]]$split <- if (identical(man$tiles[[1]]$split, "train")) "test" else "train"
  jsonlite::write_json(man, file.path(dest, "training-manifest.json"), auto_unbox = TRUE,
                       null = "null", digits = NA)
  expect_identical(at_training_check(dest)$status[1:2], c("fail", "fail"))
})

test_that("predictions import as staged, provenance-tagged ROIs and never overwrite reviews", {
  sess <- train_session(1)
  proj <- sess$projects[[1]]
  pred <- matrix(0L, 30, 40)
  pred[5:10, 5:15] <- 2L
  pred[20:25, 30:38] <- 1L
  map <- c(tumour = 1L, stroma = 2L)
  model <- list(name = "unet", version = "1.2", sha256 = strrep("a", 64))
  st <- at_training_import(proj, pred, map, model = model)
  expect_s3_class(st, "at_staged_patch")
  expect_identical(st$summary$create, 2L)
  expect_identical(at_annotation_revision(proj), st$base_revision)
  new <- Filter(function(r) r$source == "dnn_prediction", st$proposed$layers$predictions$rois)
  expect_setequal(vapply(new, `[[`, character(1), "label"), c("tumour", "stroma"))
  expect_identical(new[[1]]$attributes$review_status, "unreviewed")
  expect_identical(new[[1]]$attributes$prediction$model_sha256, strrep("a", 64))
  expect_identical(attr(st, "prediction_digest"),
                   unname(tools::sha256sum(bytes = writeBin(as.integer(pred), raw(), size = 4L,
                                                            endian = "little"))))
  stroma <- Filter(function(r) r$label == "stroma", new)[[1]]
  expect_equal(at_roi_area(stroma), 6 * 11)

  expect_identical(tryCatch(at_training_import(proj, pred[1:10, ], map), error = function(e) e$code),
                   "MASK_DIMENSIONS")
  bad <- pred; bad[1, 1] <- 7L
  expect_identical(tryCatch(at_training_import(proj, bad, map), error = function(e) e$code),
                   "LABEL_OUT_OF_RANGE")
  frac <- pred + 0.5
  expect_identical(tryCatch(at_training_import(proj, frac, map), error = function(e) e$code),
                   "DTYPE_INVALID")
  conf <- matrix(0.9, 30, 40)
  conf[20:25, 30:38] <- 0.2
  low <- at_training_import(proj, pred, map, confidence = conf, min_confidence = 0.5)
  expect_identical(low$summary$create, 1L)

  reviewed <- at_add_layer(proj, at_layer("predictions", labels = names(map)))
  kept <- at_roi_rect(0, 0, 3, 3, label = "tumour", id = "human-1", review_status = "reviewed")
  reviewed <- at_add_roi(reviewed, "predictions", kept)
  rep <- at_training_import(reviewed, pred, map, replace = TRUE)
  expect_identical(rep$operations$op[rep$operations$roi_id == "human-1"], "conflict")
  expect_false(is.null(.find_roi(rep$proposed, "human-1")))
})

# ---- Regression tests from the 2026-10 audit ---------------------------------

test_that("the training manifest is compact and checked before it replaces a dataset (X8)", {
  sess <- train_session(1)
  dest <- file.path(withr::local_tempdir(), "ds")
  at_training_export(sess, dest, tile_size = 10, fractions = c(train = 1))
  expect_length(readLines(file.path(dest, "training-manifest.json")), 1L)
  expect_gt(.interop_limits()$training_max_json_bytes, .interop_limits()$handoff_max_json_bytes)
  before <- unname(tools::md5sum(file.path(dest, "training-manifest.json")))
  local_mocked_bindings(at_training_check = function(...) stop("check failed"))
  expect_error(at_training_export(sess, dest, tile_size = 20, fractions = c(train = 1),
                                  overwrite = TRUE), "check failed")
  expect_identical(unname(tools::md5sum(file.path(dest, "training-manifest.json"))), before)
  expect_identical(list.files(dirname(dest), all.files = TRUE, no.. = TRUE), "ds")
})

test_that("a failed dataset replacement restores the previous dataset (X9)", {
  sess <- train_session(1)
  dest <- file.path(withr::local_tempdir(), "ds")
  at_training_export(sess, dest, tile_size = 10, fractions = c(train = 1))
  before <- unname(tools::md5sum(file.path(dest, "training-manifest.json")))
  real <- .rename_path
  local_mocked_bindings(.rename_path = function(from, to) {
    if (grepl("\\.partial-", basename(from))) FALSE else real(from, to)
  })
  err <- tryCatch(at_training_export(sess, dest, tile_size = 20, fractions = c(train = 1),
                                     overwrite = TRUE), error = function(e) e)
  expect_identical(err$code, "WRITE_FAILED")
  expect_identical(unname(tools::md5sum(file.path(dest, "training-manifest.json"))), before)
  expect_identical(list.files(dirname(dest), all.files = TRUE, no.. = TRUE), "ds")
})

test_that("malformed manifests become failing checks, and unsafe tile paths are never read (X13)", {
  sess <- train_session(1)
  dest <- file.path(withr::local_tempdir(), "ds")
  at_training_export(sess, dest, tile_size = 10, fractions = c(train = 1))
  man <- jsonlite::read_json(file.path(dest, "training-manifest.json"))
  inc <- which(vapply(man$tiles, function(t) identical(t$status, "included"), logical(1)))
  man$tiles[[inc[1]]]$entry_id <- "entry-9999"
  man$tiles[[inc[2]]]$mask_file <- "../outside.tif"
  jsonlite::write_json(man, file.path(dest, "training-manifest.json"), auto_unbox = TRUE,
                       null = "null", digits = NA)
  chk <- at_training_check(dest)
  expect_s3_class(chk, "at_training_check")
  expect_identical(chk$status[chk$check == "split_leakage"], "fail")
  expect_identical(chk$status[chk$check == "mask_dimensions"], "fail")
  expect_match(chk$detail[chk$check == "mask_dimensions"], "1 with unsafe paths")
  inv <- jsonlite::read_json(file.path(dest, "integrity.json"))
  inv$files[[1]]$path <- "../escape"
  jsonlite::write_json(inv, file.path(dest, "integrity.json"), auto_unbox = TRUE)
  chk2 <- at_training_check(dest)
  expect_match(chk2$detail[chk2$check == "integrity"], "unsafe path")
})

test_that("split names are safe directory names; explicit splits accept entry ids (X14)", {
  sess <- train_session(2)
  base <- withr::local_tempdir()
  err <- tryCatch(at_training_export(sess, file.path(base, "ds"), tile_size = 10,
                                     fractions = c("../../escaped" = 1)), error = function(e) e)
  expect_identical(err$code, "SPLIT_NAME_INVALID")
  expect_length(list.files(base, all.files = TRUE, no.. = TRUE), 0L)
  ds <- at_training_export(sess, file.path(base, "ds"), tile_size = 10,
                           split = list(train = "entry-0001", test = "entry-0002"))
  expect_identical(vapply(ds$manifest$images, `[[`, character(1), "split"), c("train", "test"))
  err <- tryCatch(at_training_export(sess, file.path(base, "ds2"), tile_size = 10,
                                     split = list(train = c("entry-0001", "entry-0002"),
                                                  test = "entry-0002")),
                  error = function(e) e)
  expect_identical(err$code, "SPLIT_LEAKAGE")
})

test_that("instance tiles are written at the declared 16-bit dtype (X17)", {
  sess <- train_session(1)
  dest <- file.path(withr::local_tempdir(), "ds")
  ds <- at_training_export(sess, dest, tile_size = 10, mask_type = "instance", fractions = c(train = 1))
  expect_identical(ds$manifest$mask_encoding$dtype, "uint16")
  t1 <- Filter(function(t) t$status == "included", ds$manifest$tiles)[[1]]
  m <- tiff::readTIFF(file.path(dest, t1$mask_file), info = TRUE, as.is = TRUE)
  expect_identical(as.integer(attr(m, "bits.per.sample")), 16L)
})

test_that("only overlaps of different classes are ambiguous in semantic masks (X17)", {
  sess <- train_session(1)
  p <- sess$projects[[1]]
  # A second tumour ROI overlapping the first: same class, not ambiguous.
  p <- at_add_roi(p, "tissue", at_roi_rect(4, 4, 8, 8, label = "tumour", id = "t-extra"))
  sess$projects[[1]] <- p
  ds <- at_training_export(sess, file.path(withr::local_tempdir(), "ds"), tile_size = 10,
                           fractions = c(train = 1))
  expect_identical(ds$manifest$counts$flagged$ambiguous, 0L)
  inst <- at_training_export(sess, file.path(withr::local_tempdir(), "di"), tile_size = 10,
                             mask_type = "instance", fractions = c(train = 1))
  expect_gt(inst$manifest$counts$flagged$ambiguous, 0L)
})

test_that("bands are validated and image tiles need one shared band table (X17)", {
  sess <- train_session(2)
  err <- tryCatch(at_training_export(sess, file.path(withr::local_tempdir(), "ds"), tile_size = 10,
                                     bands = 4L, fractions = c(train = 1)), error = function(e) e)
  expect_identical(err$code, "BAND_OUT_OF_RANGE")
  img <- sess$projects[[2]]$image
  img$n_bands <- 1L
  img$handle$data <- img$handle$data[, , 1, drop = FALSE]
  sess$projects[[2]]$image <- img
  err <- tryCatch(at_training_export(sess, file.path(withr::local_tempdir(), "ds"), tile_size = 10,
                                     include_images = TRUE, fractions = c(train = 1)),
                  error = function(e) e)
  expect_identical(err$code, "BAND_MISMATCH")
})

test_that("a single group of an even split goes to the first split (X20)", {
  expect_identical(unname(.assign_splits("g", c(train = 0.5, test = 0.5), 1L)), "train")
  expect_identical(unname(.assign_splits(c("a", "b"), c(train = 0.5, test = 0.5), 1L)),
                   c("train", "test"))
})

test_that("min_confidence without a confidence matrix is refused (X20)", {
  proj <- train_session(1)$projects[[1]]
  pred <- matrix(0L, 30, 40)
  pred[5:10, 5:15] <- 1L
  expect_error(at_training_import(proj, pred, c(tumour = 1L), min_confidence = 0.5),
               "confidence")
})

test_that("tile files below a symbolic link are never opened (X13)", {
  skip_on_os("windows")
  sess <- train_session(1)
  dest <- file.path(withr::local_tempdir(), "ds")
  ds <- at_training_export(sess, dest, tile_size = 10, fractions = c(train = 1))
  outside <- withr::local_tempdir()
  file.rename(file.path(dest, "masks"), file.path(outside, "masks"))
  file.symlink(file.path(outside, "masks"), file.path(dest, "masks"))
  chk <- at_training_check(dest)
  expect_identical(chk$status[chk$check == "integrity"], "fail")
  expect_match(chk$detail[chk$check == "integrity"], "symbolic link")
  expect_identical(chk$status[chk$check == "mask_dimensions"], "fail")
  expect_match(chk$detail[chk$check == "mask_dimensions"], "with unsafe paths")
})
