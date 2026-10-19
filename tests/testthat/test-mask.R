# The mask engine is the core deliverable; this is the largest test file.

test_that("the pixel-coverage contract holds on a hand-verified case", {
  # Rect x[2,5], y[2,5] on a 10x10 grid. Pixel (i,j) centre = (j-0.5, i-0.5),
  # so centres in (2,5) => i,j in {3,4,5}. Exactly nine pixels.
  m <- at_mask(at_roi_rect(2, 2, 5, 5, label = "a"), "binary", dims = c(10, 10))
  expect_equal(sum(m), 9L)
  idx <- which(as.matrix(m), arr.ind = TRUE)
  expect_identical(sort(unique(idx[, 1])), 3:5)
  expect_identical(sort(unique(idx[, 2])), 3:5)
})

test_that("boundary ties resolve as [lower, upper) symmetrically", {
  # Edges exactly on pixel centres x=2.5..5.5: lower centre included, upper
  # excluded -> rows and cols 3,4,5.
  m <- at_mask(at_roi_rect(2.5, 2.5, 5.5, 5.5, label = "a"), "binary", dims = c(10, 10))
  idx <- which(as.matrix(m), arr.ind = TRUE)
  expect_identical(sort(unique(idx[, 1])), 3:5)
  expect_identical(sort(unique(idx[, 2])), 3:5)
})

test_that("touches = TRUE grows the region beyond centre coverage", {
  r <- at_roi_rect(2.6, 2.6, 4.4, 4.4, label = "a")
  mf <- at_mask(r, "binary", dims = c(10, 10), touches = FALSE)
  mt <- at_mask(r, "binary", dims = c(10, 10), touches = TRUE)
  expect_equal(sum(mf), 1L)
  expect_equal(sum(mt), 9L)
})

test_that("the three mask types return the right structure", {
  proj <- demo_project()
  mb <- at_mask(proj, "binary")
  ml <- at_mask(proj, "labelled")
  mc <- at_mask(proj, "multiclass")
  expect_true(is.logical(as.matrix(mb)))
  expect_true(is.integer(as.matrix(ml)))
  expect_equal(nrow(at_mask_legend(ml)), 3L) # one id per ROI
  expect_equal(nrow(at_mask_legend(mc)), 2L) # one id per label
})

test_that("overlap policies resolve deterministically", {
  a <- at_roi_rect(0, 0, 6, 6, label = "a")
  b <- at_roi_rect(4, 4, 10, 10, label = "b")
  lyr <- at_layer_add(at_layer_add(at_layer("l"), a), b)
  expect_equal(as.matrix(at_mask(lyr, "labelled", dims = c(10, 10), overlap = "last"))[5, 5], 2L)
  expect_equal(as.matrix(at_mask(lyr, "labelled", dims = c(10, 10), overlap = "first"))[5, 5], 1L)
  expect_equal(as.matrix(at_mask(lyr, "labelled", dims = c(10, 10), overlap = "max"))[5, 5], 2L)
  expect_equal(as.matrix(at_mask(lyr, "labelled", dims = c(10, 10), overlap = "min"))[5, 5], 1L)
  expect_error(at_mask(lyr, "labelled", dims = c(10, 10), overlap = "error"), "Overlapping")
})

test_that("an empty project gives an all-background mask of correct type/dims", {
  proj <- at_project(small_image())
  ml <- at_mask(proj, "labelled")
  expect_identical(dim(ml), c(100L, 100L))
  expect_true(all(as.matrix(ml) == 0L))
  expect_equal(nrow(at_mask_legend(ml)), 0L)
  mb <- at_mask(proj, "binary")
  expect_true(is.logical(as.matrix(mb)))
  expect_false(any(as.matrix(mb)))
})

test_that("terra and stars rasterisers are bit-identical", {
  skip_if_not_installed("terra")
  proj <- demo_project()
  for (ty in c("binary", "labelled", "multiclass")) {
    ms <- as.matrix(at_mask(proj, ty, engine = "stars"))
    mt <- as.matrix(at_mask(proj, ty, engine = "terra"))
    expect_identical(ms, mt, info = ty)
  }
  # And on a boundary-tie case.
  r <- at_roi_rect(2.5, 2.5, 5.5, 5.5, label = "a")
  expect_identical(
    as.matrix(at_mask(r, "binary", dims = c(10, 10), engine = "stars")),
    as.matrix(at_mask(r, "binary", dims = c(10, 10), engine = "terra"))
  )
})

test_that("mask at level 2 has level-2 dims and aligns with level 0", {
  img <- small_image() # 100, 50, 25
  lyr <- at_layer_add(at_layer("l"), at_roi_rect(20, 20, 60, 60, label = "a"))
  proj <- at_project(img, lyr)
  m0 <- as.matrix(at_mask(proj, "binary", level = 0))
  m2 <- as.matrix(at_mask(proj, "binary", level = 2))
  expect_identical(dim(m2), c(25L, 25L))
  # Upsample level 2 by 4 and compare: mismatch confined to a thin boundary.
  up <- m2[rep(seq_len(25), each = 4), rep(seq_len(25), each = 4)]
  mismatch <- mean(up != m0)
  expect_lt(mismatch, 0.1)
})

test_that("level masking uses real image dims for non-power-of-two pyramids", {
  img <- new_annot_image("np.tif", "tiff", c(100L, 100L), 3L,
                         list(c(100L, 100L), c(40L, 40L), c(16L, 16L)), 1L)
  proj <- at_project(img, at_layer_add(at_layer("l"),
                                       at_roi_rect(0, 0, 50, 50, label = "a")))
  m1 <- at_mask(proj, "binary", level = 1)
  expect_identical(dim(m1), c(40L, 40L))
  # 50 * (40/100) = 20, not the power-of-two 25.
  idx <- which(as.matrix(m1), arr.ind = TRUE)
  expect_equal(max(idx[, 2]), 20L)
})

test_that("the legend is populated with the contracted columns", {
  lg <- at_mask_legend(at_mask(demo_project(), "labelled"))
  expect_identical(names(lg), c("value", "label", "layer", "roi_id", "n_px", "colour"))
  expect_true(all(lg$n_px > 0))
})

test_that("at_mask_stats is type-stable and correct", {
  m <- at_mask(at_roi_rect(2, 2, 5, 5, label = "a"), "labelled", dims = c(10, 10))
  st <- at_mask_stats(m)
  expect_equal(st$n_px, 9L)
  expect_equal(st$area_px, 9)
  expect_true(is.na(st$area_physical))
  st2 <- at_mask_stats(m, pixel_size = c(2, 2))
  expect_equal(st2$area_physical, 36)
  # empty
  empty <- at_mask_stats(at_mask(at_project(small_image()), "labelled"))
  expect_equal(nrow(empty), 0L)
  expect_identical(names(empty)[1:3], c("value", "label", "n_px"))
})

test_that("at_mask_boundary marks object edges", {
  m <- at_mask(at_roi_rect(2, 2, 8, 8, label = "a"), "labelled", dims = c(10, 10))
  b <- at_mask_boundary(m)
  expect_true(is.matrix(b) && is.logical(b))
  expect_true(sum(b) > 0 && sum(b) < sum(as.matrix(m) != 0))
})

test_that("at_mask_preview downsamples nearest-neighbour", {
  proj <- demo_project()
  m <- at_mask(proj, "labelled")
  pv <- at_mask_preview(m, max_dim = 25)
  expect_true(max(dim(pv)) <= 25L)
  expect_true(all(unique(as.integer(pv)) %in% unique(as.integer(m))))
})

test_that("at_mask_stack has one plane per layer", {
  proj <- demo_project()
  stk <- at_mask_stack(proj)
  expect_length(dim(stk), 3L)
  expect_identical(dim(stk)[3], length(proj$layers))
})

test_that("at_mask errors on unsupported input", {
  expect_error(at_mask(1), "annot_roi")
})

test_that("plot.annot_mask returns a ggplot", {
  expect_s3_class(plot(at_mask(demo_project(), "labelled")), "ggplot")
  expect_s3_class(plot(at_mask(demo_project(), "labelled"), legend = FALSE), "ggplot")
})

test_that("at_mask derives dims from the geometry bbox when none are given", {
  m <- at_mask(at_roi_rect(2, 2, 8, 8, label = "a"), "binary")
  expect_identical(dim(m), c(8L, 8L))
})

test_that("annot_mask print, dim, as.matrix, and summary work", {
  m <- at_mask(demo_project(), "labelled")
  expect_output(print(m), "annot_mask")
  expect_identical(dim(m), c(100L, 100L))
  expect_true(is.matrix(as.matrix(m)))
  expect_s3_class(summary(m), "tbl_df")
})

test_that("at_mask_boundary supports a thicker boundary", {
  m <- at_mask(at_roi_rect(2, 2, 18, 18, label = "a"), "labelled", dims = c(20, 20))
  expect_gt(sum(at_mask_boundary(m, width = 2L)), sum(at_mask_boundary(m, width = 1L)))
})

test_that("at_mask_stack is empty for a layerless project", {
  stk <- at_mask_stack(at_project(small_image()))
  expect_identical(dim(stk)[3], 0L)
})

test_that("at_mask_stats reports zero pixels for a fully occluded label", {
  # ROI 'a' is completely covered by 'b' under overlap = "last".
  a <- at_roi_rect(2, 2, 6, 6, label = "a")
  b <- at_roi_rect(0, 0, 10, 10, label = "b")
  lyr <- at_layer_add(at_layer_add(at_layer("l"), a), b)
  m <- at_mask(lyr, "labelled", dims = c(10, 10), overlap = "last")
  st <- at_mask_stats(m)
  expect_true(0L %in% st$n_px)
})

test_that("mask plots put pixel (i, j) on [j-1, j) x [i-1, i)", {
  m <- at_mask(at_roi_rect(2, 1, 3, 2, label = "a"), "labelled", dims = c(4, 3))
  layers <- ggplot2::ggplot_build(at_plot_mask(m))$data
  # Layer 1 frames the whole 4 x 3 grid; layer 2 holds the foreground tiles.
  expect_equal(c(layers[[1]]$xmin, layers[[1]]$xmax), c(0, 4))
  expect_equal(sort(c(-layers[[1]]$ymin, -layers[[1]]$ymax)), c(0, 3))
  built <- layers[[2]]
  expect_equal(c(built$xmin, built$xmax), c(2, 3))
  expect_equal(sort(c(-built$ymin, -built$ymax)), c(1, 2))
})

test_that("bitfield defaults use single bits and labelled bitor is refused (M7)", {
  lyr <- at_layer_add(at_layer("a"), at_roi_rect(0, 0, 6, 6, label = "s"))
  lyr <- at_layer_add(lyr, at_roi_rect(4, 4, 10, 10, label = "b"))
  lyr <- at_layer_add(lyr, at_roi_rect(8, 0, 10, 2, label = "c"))
  m <- at_mask(lyr, "multiclass", overlap = "bitor", dims = c(10, 10))
  lg <- at_mask_legend(m)
  expect_identical(lg$value, c(1L, 2L, 4L))
  # The s/b overlap is 1 | 2, distinct from class c (4).
  expect_identical(as.matrix(m)[5, 5], 3L)
  expect_identical(lg$n_px[lg$label == "c"], 4L)
  expect_identical(attr(m, "mask_metadata")$encoding, "bitfield")
  expect_error(at_mask(lyr, "labelled", overlap = "bitor", dims = c(10, 10)), "multiclass")
})

test_that("unknown layer names are errors, not empty masks", {
  proj <- demo_project()
  expect_error(at_mask(proj, layer = "typo"), class = "at_validation_error")
  expect_error(at_mask(proj, layer = c("tissue", "typo")), "typo")
  expect_error(at_mask_stack(proj, layers = "typo"), "typo")
  expect_identical(dim(at_mask_stack(proj, layers = "tumour"))[3], 1L)
})

test_that("at_mask_stack keeps each layer's legend", {
  proj <- demo_project()
  stk <- at_mask_stack(proj)
  lgs <- attr(stk, "legends")
  expect_identical(names(lgs), dimnames(stk)[[3]])
  expect_identical(lgs$tumour$label, "tumour")
  expect_identical(lgs$tumour$n_px, as.integer(sum(stk[, , "tumour"] == lgs$tumour$value)))
})

test_that("mask statistics match an independent per-value scan", {
  set.seed(42)
  m <- matrix(sample(c(0L, 3L, 7L, 9L), 12 * 8, replace = TRUE), 8, 12)
  lg <- tibble::tibble(value = c(3L, 7L, 9L, 11L), label = c("a", "b", "c", "absent"))
  mask <- .new_annot_mask(m, lg, 0L, c(12L, 8L), "multiclass", encoding = "categorical")
  st <- at_mask_stats(mask, pixel_size = 0.5)
  for (k in seq_len(nrow(lg))) {
    idx <- which(m == lg$value[k], arr.ind = TRUE)
    expect_identical(st$n_px[k], nrow(idx))
    if (nrow(idx)) {
      expect_equal(st$centroid_x[k], mean(idx[, 2] - 0.5))
      expect_equal(st$centroid_y[k], mean(idx[, 1] - 0.5))
      expect_equal(c(st$bbox_xmin[k], st$bbox_xmax[k]), c(min(idx[, 2]) - 1, max(idx[, 2])))
      expect_equal(c(st$bbox_ymin[k], st$bbox_ymax[k]), c(min(idx[, 1]) - 1, max(idx[, 1])))
    }
    # A single pixel size means square pixels.
    expect_equal(st$area_physical[k], nrow(idx) * 0.25)
  }
  expect_error(at_mask_stats(mask, pixel_size = c(1, 1, 1)), "pixel_size")
  expect_error(at_mask_stats(mask, pixel_size = -1), "pixel_size")
})

test_that("all-touched masks of mixed points and polygons work with both engines", {
  skip_if_not_installed("terra")
  lyr <- at_layer_add(at_layer_add(at_layer("l"), at_roi_rect(1, 1, 4, 4, label = "a")),
                      at_roi_point(6.5, 6.5, label = "p"))
  for (engine in c("stars", "terra")) {
    m <- as.matrix(at_mask(lyr, "labelled", dims = c(10, 10), touches = TRUE, engine = engine))
    expect_identical(sum(m == 1L), 9L, info = engine)
    expect_identical(which(m == 2L), 67L, info = engine) # row 7, column 7
  }
})
