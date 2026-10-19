test_that("project RDS round-trips identically", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".rds")
  at_save_project(proj, p)
  p2 <- at_load_project(p)
  expect_equal(at_rois(proj)$geometry, at_rois(p2)$geometry)
  expect_identical(at_rois(proj)$label, at_rois(p2)$label)
  expect_equal(at_layers(proj), at_layers(p2))
})

test_that("a newer-version file triggers a migration warning", {
  proj <- demo_project()
  proj$provenance$saved_with <- "99.0.0"
  p <- withr::local_tempfile(fileext = ".rds")
  saveRDS(proj, p)
  expect_warning(at_load_project(p), "newer")
})

test_that("at_save_project refuses to clobber", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".rds")
  at_save_project(proj, p)
  expect_error(at_save_project(proj, p), "already exists")
})

test_that("session save/load round-trips", {
  sess <- demo_session(3)
  sess <- at_set_status(sess, 1, "complete")
  at_save_session(sess)
  loaded <- at_load_session(file.path(sess$out_dir, "_session.rds"))
  expect_s3_class(loaded, "annot_session")
  expect_identical(at_session_status(loaded)$status[1], "complete")
})

# ---- Persistence contract (audit A01, A23, C1, C4) -------------------------

# A session over real files, as an app or script would build it.
real_session <- function(n = 1L) {
  skip_if_not_installed("magick")
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  paths <- file.path(dir, sprintf("img_%d.png", seq_len(n)))
  for (p in paths) file.copy(at_example_path("tissue"), p)
  at_session(paths, labels = "a", out_dir = dir)
}

test_that("a resumed session reopens images saved without pixels (A01)", {
  s <- real_session()
  p <- at_current(s)
  want <- at_tile(p$image, xrange = c(1, 4), yrange = c(1, 4))
  s$projects[[1]] <- at_add_roi(p, names(p$layers)[1], at_roi_rect(1, 1, 5, 5, label = "a"))
  at_save_session(s)
  # The file holds annotations, not the decoded image.
  stored <- readRDS(file.path(s$out_dir, "_session.rds"))
  expect_null(stored$projects[[1]]$image$handle)
  expect_identical(stored$projects[[1]]$image$source_descriptor$backend, "raster")
  # A fresh process has an empty tile cache.
  .tile_cache_clear()
  s2 <- at_resume(file.path(s$out_dir, "_session.rds"))
  cur <- at_current(s2)
  expect_false(is.null(cur$image$handle))
  expect_identical(at_tile(cur$image, xrange = c(1, 4), yrange = c(1, 4)), want)
  # Even a stripped image passed straight to at_tile() is served.
  expect_identical(at_tile(s2$projects[[1]]$image, xrange = c(1, 4), yrange = c(1, 4)), want)
  expect_equal(nrow(at_rois(cur)), 1L)
})

test_that("a resumed session is usable in a genuinely fresh R process", {
  skip_on_cran()
  skip_if_not_installed("callr")
  root <- normalizePath(test_path("..", ".."), mustWork = FALSE)
  if (!file.exists(file.path(root, "DESCRIPTION")) ||
      length(list.files(file.path(root, "R"), pattern = "[.]R$")) == 0L) {
    skip("needs the package source tree for a development load")
  }
  s <- real_session()
  p <- at_current(s)
  want <- at_tile(p$image, xrange = c(1, 4), yrange = c(1, 4))
  s$projects[[1]] <- p
  at_save_session(s)
  got <- callr::r(function(root, path) {
    suppressMessages(pkgload::load_all(root, quiet = TRUE))
    s2 <- at_resume(path)
    p2 <- at_current(s2)
    p2 <- at_add_roi(p2, names(p2$layers)[1], at_roi_rect(2, 2, 6, 6, label = "a"))
    list(tile = at_tile(p2$image, xrange = c(1, 4), yrange = c(1, 4)),
         ids = .all_roi_ids(p2))
  }, args = list(root = root, path = file.path(s$out_dir, "_session.rds")))
  expect_identical(got$tile, want)
  expect_length(got$ids, 1L)
})

test_that("a hand-built image keeps its pixels when saved", {
  img <- new_annot_image("not-a-file.tif", "raster", c(4L, 4L), 1L, list(c(4L, 4L)), 1L,
                         handle = list(data = array(7, c(4, 4, 1))))
  p <- withr::local_tempfile(fileext = ".rds")
  at_save_project(at_project(img), p)
  back <- at_load_project(p)
  expect_identical(max(at_tile(back$image)), 7)
})

test_that("a source that changed shape keeps annotations but refuses pixels", {
  skip_if_not_installed("magick")
  dir <- withr::local_tempdir()
  f <- file.path(dir, "img.png")
  file.copy(at_example_path("tissue"), f)
  proj <- at_add_roi(at_project(at_read_image(f), at_layer("l")), "l",
                     at_roi_rect(1, 1, 5, 5, label = "a"))
  p <- file.path(dir, "p.rds")
  at_save_project(proj, p)
  magick::image_write(magick::image_blank(7, 5, "white"), f, format = "png")
  Sys.setFileTime(f, Sys.time() + 5)
  back <- at_load_project(p)
  expect_equal(nrow(at_rois(back)), 1L)
  expect_identical(at_inspect_source(back)$status, "changed")
  err <- tryCatch(at_tile(back$image), error = identity)
  expect_s3_class(err, "at_io_error")
  expect_identical(err$code, "IMAGE_CHANGED")
  expect_match(conditionMessage(err), "at_relink_source")
  # Relinking to a file with other dimensions is refused; annotations stay.
  expect_error(at_relink_source(back, f), "differ")
})

test_that("a missing source gives IMAGE_UNAVAILABLE, not an empty tile", {
  skip_if_not_installed("magick")
  dir <- withr::local_tempdir()
  f <- file.path(dir, "img.png")
  file.copy(at_example_path("tissue"), f)
  p <- file.path(dir, "p.rds")
  at_save_project(at_project(at_read_image(f)), p)
  unlink(f)
  back <- at_load_project(p)
  err <- tryCatch(at_tile(back$image, xrange = c(1, 2), yrange = c(1, 2)), error = identity)
  expect_s3_class(err, "at_io_error")
  expect_identical(err$code, "IMAGE_UNAVAILABLE")
})

test_that("loading advances the id counter past loaded ids (A07)", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".rds")
  at_save_project(proj, p)
  .reset_id_counter()
  back <- at_load_project(p)
  fresh <- at_roi_point(1, 1, label = "tissue")
  expect_false(fresh$id %in% .all_roi_ids(back))
})

test_that("the default session path honours overwrite = FALSE (A23)", {
  sess <- demo_session(2)
  at_save_session(sess)
  expect_error(at_save_session(sess), "already exists")
  expect_no_error(at_save_session(sess, overwrite = TRUE))
  expect_error(at_save_session(sess, overwrite = NA), class = "at_validation_error")
})

test_that("a failed save keeps the previous checkpoint intact", {
  skip_on_os("windows")
  sess <- demo_session(2)
  at_save_session(sess)
  path <- file.path(sess$out_dir, "_session.rds")
  before <- readRDS(path)
  Sys.chmod(sess$out_dir, "0555")
  withr::defer(Sys.chmod(sess$out_dir, "0755"))
  if (file.access(sess$out_dir, 2L) == 0L) skip("cannot make the directory read-only here")
  sess2 <- at_set_status(sess, 1, "complete")
  err <- tryCatch(at_save_session(sess2, overwrite = TRUE), error = identity)
  expect_s3_class(err, "at_io_error")
  expect_identical(err$code, "WRITE_FAILED")
  expect_identical(readRDS(path)$manifest$status, before$manifest$status)
  expect_length(list.files(sess$out_dir, pattern = "partial", all.files = TRUE), 0L)
})
