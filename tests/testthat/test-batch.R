skip_if_not_installed("tiff")

test_that("at_export_all writes every format in the right layout", {
  sess <- at_example_session(3)
  dir <- withr::local_tempdir()
  receipt <- suppressMessages(at_export_all(sess, dir, scope = "all", progress = FALSE))
  expect_s3_class(receipt, "tbl_df")
  expect_identical(names(receipt),
                   c("entry_id", "image", "format", "path", "bytes", "n_rois", "status", "message", "sidecar_path", "sidecar_bytes"))
  expect_setequal(list.dirs(dir, recursive = FALSE, full.names = FALSE),
                  c("masks", "geojson", "qupath", "projects", "csv"))
  expect_true(file.exists(file.path(dir, "_export_manifest.csv")))
  expect_true(file.exists(file.path(dir, "_annotation_summary.csv")))
})

test_that("the export receipt is accurate", {
  sess <- at_example_session(2)
  dir <- withr::local_tempdir()
  receipt <- suppressMessages(at_export_all(sess, dir, scope = "all",
                                            formats = c("geojson", "csv"), progress = FALSE))
  ok <- receipt[receipt$status == "ok", ]
  expect_true(all(file.exists(ok$path)))
  expect_true(all(ok$bytes > 0))
})

test_that("a mid-batch failure is isolated in the receipt", {
  sess <- at_example_session(4)
  file.remove(at_session_status(sess)$path[3])
  dir <- withr::local_tempdir()
  receipt <- suppressWarnings(suppressMessages(
    at_export_all(sess, dir, scope = "all", progress = FALSE)
  ))
  bad <- at_session_status(sess)$name[3]
  expect_true(any(receipt$image == bad & receipt$status == "error"))
  expect_true(any(receipt$status == "ok"))
})

test_that("at_manifest label counts match at_rois aggregation", {
  sess <- at_example_session(2)
  sess$projects[[1]] <- at_example_project()
  man <- at_manifest(sess)
  expect_true(all(c("idx", "entry_id", "export_stem", "name", "path", "status",
                    "n_layers", "n_rois") %in% names(man)))
  rt <- at_rois(sess$projects[[1]])
  for (lb in c("tumour", "necrosis", "stroma")) {
    expect_identical(man[[lb]][1], sum(rt$label == lb))
  }
})

test_that("at_batch_apply modifies all projects and returns a session", {
  sess <- at_example_session(3)
  relabel <- function(project, image, idx, ...) {
    rt <- at_rois(project)
    project # identity keeps materialisation but exercises the path
  }
  out <- at_batch_apply(sess, relabel, progress = FALSE)
  expect_s3_class(out, "annot_session")
  expect_true(all(!vapply(out$projects, is.null, logical(1))))
})

test_that("at_batch_check_geometry flags broken geometry and is clean otherwise", {
  sess <- at_example_session(2)
  sess$projects[[1]] <- broken_project("self_intersect")
  bv <- at_batch_check_geometry(sess)
  expect_identical(names(bv), c("image", "roi_id", "issue", "severity"))
  expect_true("self_intersection" %in% bv$issue)
  # A clean session yields 0 rows.
  clean <- at_example_session(2)
  clean$projects[[1]] <- at_example_project()
  expect_equal(nrow(at_batch_check_geometry(clean)), 0L)
})

test_that("at_summary_table aggregates by the chosen key", {
  sess <- at_example_session(2)
  sess$projects[[1]] <- at_example_project()
  st <- at_summary_table(sess, by = "label")
  expect_true(all(c("label", "n_rois", "total_area_px", "mean_area", "sd_area") %in% names(st)))
  expect_setequal(st$label, c("tumour", "necrosis", "stroma"))
  # Empty session -> 0 rows with the key column.
  empty <- at_summary_table(at_example_session(2), by = "image")
  expect_equal(nrow(empty), 0L)
  expect_identical(names(empty)[1], "image")
})

# ---- Export identity and batch error isolation (audit A08, M20) ------------

test_that("images sharing a base name export to distinct files (A08)", {
  skip_if_not_installed("magick")
  d1 <- withr::local_tempdir()
  d2 <- withr::local_tempdir()
  d3 <- withr::local_tempdir() # own directory: macOS file systems ignore case
  for (d in c(d1, d2)) file.copy(at_example_path("tissue"), file.path(d, "same.png"))
  file.copy(at_example_path("tissue"), file.path(d3, "SAME.png"))
  s <- at_session(file.path(c(d1, d2, d3), c("same.png", "same.png", "SAME.png")),
                  labels = "a", out_dir = d1)
  for (i in 1:3) {
    p <- at_current(at_goto(s, i))
    s$projects[[i]] <- at_add_roi(p, names(p$layers)[1],
                                  at_roi_rect(i, i, i + 4, i + 4, label = "a"))
  }
  out <- file.path(d1, "out")
  r <- at_export_all(s, out, formats = c("geojson", "rds"), scope = "all",
                     progress = FALSE, overwrite = TRUE)
  expect_true(all(r$status == "ok"))
  expect_identical(r$image, rep(c("same", "same", "SAME"), each = 2L))
  geo <- r$path[r$format == "geojson"]
  expect_length(unique(tolower(geo)), 3L)
  expect_true(all(file.exists(geo)))
  # Each file holds its own image's ROI.
  xs <- vapply(geo, function(p) {
    sf::st_bbox(at_read_geojson(p)[[1]]$rois[[1]]$geometry)[["xmin"]]
  }, numeric(1))
  expect_equal(unname(xs), c(1, 2, 3))
})

test_that("unsafe display names cannot escape the export directory", {
  skip_if_not_installed("magick")
  d <- withr::local_tempdir()
  f <- file.path(d, "img.png")
  file.copy(at_example_path("tissue"), f)
  s <- at_session(f, labels = "a", out_dir = d)
  s$manifest$name <- "../escaped"
  out <- file.path(d, "out")
  r <- at_export_all(s, out, formats = "geojson", scope = "all", progress = FALSE)
  expect_true(startsWith(normalizePath(r$path), normalizePath(out)))
  expect_identical(r$image, "../escaped")
})

test_that("at_export_all rejects unknown formats", {
  sess <- demo_session(1)
  expect_error(at_export_all(sess, withr::local_tempdir(), formats = "pdf",
                             scope = "all", progress = FALSE),
               class = "at_validation_error")
})

test_that("at_batch_apply isolates failures and keeps previous projects (M20)", {
  sess <- demo_session(3)
  for (i in 1:3) sess$projects[[i]] <- at_project(tiny_image(), at_layer("l"), name = paste0("p", i))
  fn <- function(p, img, i) {
    if (i == 2) return(NULL)
    if (i == 3) stop("boom")
    at_add_roi(p, "l", at_roi_rect(1, 1, 3, 3, label = "a"))
  }
  expect_warning(out <- at_batch_apply(sess, fn, progress = FALSE), "2 images")
  errs <- attr(out, "batch_errors")
  expect_identical(errs$idx, c(2L, 3L))
  expect_match(errs$message[1], "annot_project")
  expect_match(errs$message[2], "boom")
  expect_equal(nrow(at_rois(out$projects[[1]])), 1L)
  expect_identical(out$projects[[2]], sess$projects[[2]])
  ok <- at_batch_apply(sess, function(p, img, i) p, progress = FALSE)
  expect_null(attr(ok, "batch_errors"))
})
