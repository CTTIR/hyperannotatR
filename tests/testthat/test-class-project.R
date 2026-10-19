test_that("at_project builds provenance and normalises layers", {
  proj <- demo_project()
  expect_s3_class(proj, "annot_project")
  expect_identical(proj$provenance$annotatR_version, as.character(utils::packageVersion("hyperannotatR")))
  expect_named(proj$layers, c("tissue", "tumour"))
})

test_that("at_rois returns the exact contracted tibble (populated)", {
  proj <- demo_project()
  t <- at_rois(proj)
  expect_s3_class(t, "tbl_df")
  expect_equal(nrow(t), 3L)
  expect_identical(names(t), names(.empty_roi_tbl()))
  empty <- .empty_roi_tbl()
  types <- vapply(t[setdiff(names(t), "geometry")], function(x) class(x)[[1]], character(1))
  etypes <- vapply(empty[setdiff(names(empty), "geometry")], function(x) class(x)[[1]], character(1))
  expect_identical(types, etypes)
  expect_true(inherits(t$geometry, "sfc"))
})

test_that("at_rois is type-stable on empty input", {
  proj <- at_project(small_image())
  t <- at_rois(proj)
  expect_s3_class(t, "tbl_df")
  expect_equal(nrow(t), 0L)
  expect_identical(names(t), names(.empty_roi_tbl()))
})

test_that("at_rois filters by layer and label", {
  proj <- demo_project()
  expect_equal(nrow(at_rois(proj, layer = "tumour")), 1L)
  expect_equal(nrow(at_rois(proj, label = "tissue")), 2L)
  expect_equal(nrow(at_rois(proj, label = "absent")), 0L)
})

test_that("at_layers reports one row per layer, empty-safe", {
  proj <- demo_project()
  l <- at_layers(proj)
  expect_equal(nrow(l), 2L)
  expect_identical(names(l), c("name", "n_rois", "labels", "visible", "locked", "z"))
  expect_identical(l$z, c(1L, 2L))
  expect_equal(nrow(at_layers(at_project(small_image()))), 0L)
})

test_that("at_add_layer rejects duplicate names", {
  proj <- demo_project()
  expect_error(at_add_layer(proj, at_layer("tissue")), "already exists")
})

test_that("at_add_roi requires an existing layer and keeps ids unique", {
  proj <- demo_project()
  expect_error(at_add_roi(proj, "nope", at_roi_point(1, 1, label = "x")), "No layer")
  proj2 <- at_add_roi(proj, "tissue", at_roi_point(1, 1, label = "tissue"))
  ids <- at_rois(proj2)$roi_id
  expect_length(unique(ids), length(ids))
})

test_that("mutators do not modify their input", {
  proj <- demo_project()
  snapshot <- proj
  invisible(at_add_roi(proj, "tissue", at_roi_point(1, 1, label = "tissue")))
  invisible(at_remove_layer(proj, "tumour"))
  expect_identical(proj, snapshot)
})

test_that("at_remove_roi removes across layers or warns", {
  proj <- demo_project()
  id <- at_rois(proj)$roi_id[1]
  proj2 <- at_remove_roi(proj, id)
  expect_equal(nrow(at_rois(proj2)), nrow(at_rois(proj)) - 1L)
  expect_warning(at_remove_roi(proj, "no-such-id"), "nothing removed")
})

test_that("edit log grows with each mutation", {
  proj <- demo_project()
  n0 <- length(proj$provenance$edit_log)
  proj <- at_add_roi(proj, "tissue", at_roi_point(1, 1, label = "tissue"))
  expect_equal(length(proj$provenance$edit_log), n0 + 1L)
})

test_that("at_validate passes clean projects and flags duplicate ids", {
  proj <- demo_project()
  expect_s3_class(at_validate(proj), "annot_project")
  proj$layers$tissue$rois[[2]]$id <- proj$layers$tissue$rois[[1]]$id
  expect_error(at_validate(proj), "unique")
})

test_that("at_summary returns per-label counts", {
  s <- at_summary(demo_project())
  expect_s3_class(s, "annot_summary")
  expect_identical(s$n_layers, 2L)
  expect_identical(s$n_rois, 3L)
  expect_true(all(c("tissue", "tumour") %in% s$per_label$label))
})

test_that("print methods produce output", {
  expect_output(print(demo_project()), "annot_project")
  expect_output(print(at_summary(demo_project())), "annot_summary")
})

test_that("at_project rejects a non-layer layers argument", {
  expect_error(at_project(small_image(), layers = 42), "annot_layer")
  expect_error(at_project(small_image(), layers = list(1, 2)), "Every element")
})

test_that("at_rois errors on an unknown layer filter", {
  expect_error(at_rois(demo_project(), layer = "nope"), "No layer")
  expect_error(at_add_roi(demo_project(), "nope", at_roi_point(1, 1, label = "x")), "No layer")
  expect_error(at_remove_layer(demo_project(), "nope"), "No layer")
})

test_that("summary.annot_project dispatches to at_summary", {
  expect_s3_class(summary(demo_project()), "annot_summary")
})

test_that("at_project detects duplicate layer names on construction", {
  a <- at_layer("dup")
  expect_error(.normalize_layers(list(a, a)), "unique")
})

# ---- Identifier uniqueness (audit A07, C2) ---------------------------------

test_that("adding an ROI after a counter restart never duplicates an id (A07)", {
  img <- tiny_image()
  .reset_id_counter()
  l <- at_layer("l")
  for (i in 1:4) l <- at_layer_add(l, at_roi_point(i, i, label = "a"))
  proj <- at_project(img, l)
  .reset_id_counter() # what a fresh R process does
  proj <- at_add_roi(proj, "l", at_roi_point(9, 9, label = "a"))
  ids <- .all_roi_ids(proj)
  expect_false(anyDuplicated(ids) > 0L)
  expect_no_error(at_validate(proj))
})

test_that("a populated layer with clashing ids is re-minted", {
  .reset_id_counter()
  l <- at_layer("l")
  for (i in 1:2) l <- at_layer_add(l, at_roi_point(i, i, label = "a"))
  proj <- at_project(tiny_image(), l)
  m <- at_layer_add(at_layer("m"), at_roi_point(5, 5, label = "a", id = "roi_000000001"))
  proj2 <- at_add_layer(proj, m)
  expect_false(anyDuplicated(.all_roi_ids(proj2)) > 0L)
  # Removing by id now touches exactly one ROI.
  expect_equal(nrow(at_rois(at_remove_roi(proj2, "roi_000000001"))), 2L)
  # The original ROI keeps its id; the incoming one was renamed.
  expect_identical(proj2$layers$l$rois[[1]]$id, "roi_000000001")
  expect_false(proj2$layers$m$rois[[1]]$id == "roi_000000001")
})

test_that("at_project re-mints ids repeated across or within layers", {
  r <- at_roi_point(1, 1, label = "a", id = "same")
  a <- at_layer("a"); a$rois <- list(r, r)
  b <- at_layer("b"); b$rois <- list(r)
  proj <- at_project(tiny_image(), list(a, b))
  ids <- .all_roi_ids(proj)
  expect_length(ids, 3L)
  expect_false(anyDuplicated(ids) > 0L)
  expect_identical(ids[1], "same")
})

test_that("at_validate rejects ROIs at levels the image lacks or without one geometry", {
  r <- new_annot_roi(sf::st_sfc(sf::st_point(c(1, 1)), crs = sf::NA_crs_),
                     id = "r", label = "a", level = 3L)
  l <- at_layer("l"); l$rois <- list(r)
  expect_error(at_validate(at_project(tiny_image(), l)), "pyramid level")
  r$level <- 0L
  r$geometry <- sf::st_sfc(crs = sf::NA_crs_)
  l$rois <- list(r)
  expect_error(at_validate(at_project(tiny_image(), l)), "exactly one geometry")
})

test_that("at_rois handles empty geometries and many ROIs", {
  l <- at_layer("l")
  for (i in 1:30) l <- at_layer_add(l, at_roi_rect(i, i, i + 2, i + 2, label = "a"))
  e <- new_annot_roi(.empty_polygon_sfc(), id = "empty", label = "a", level = 0L)
  l$rois <- c(l$rois, list(e))
  rt <- at_rois(at_project(small_image(), l))
  expect_equal(nrow(rt), 31L)
  expect_equal(rt$area_px[1:30], rep(4, 30))
  expect_identical(rt$area_px[31], 0)
  expect_true(is.na(rt$centroid_x[31]))
  expect_identical(rt$n_vertices[31], 0L)
  expect_equal(rt$centroid_x[1], 2)
})
