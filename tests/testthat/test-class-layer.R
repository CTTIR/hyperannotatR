test_that("at_style validates and stores its fields", {
  s <- at_style(fill_alpha = 0.5, z = 3)
  expect_s3_class(s, "annot_style")
  expect_identical(s$z, 3L)
  expect_error(at_style(fill_alpha = 2), "range")
  expect_error(at_style(visible = NA), "TRUE")
})

test_that("at_layer resolves a stable colour mapping", {
  lyr <- at_layer("l", labels = c("a", "b"))
  expect_named(lyr$style$colour, c("a", "b"))
  expect_identical(unname(lyr$style$colour["a"]), "#999999")
  expect_identical(at_layer_n(lyr), 0L)
})

test_that("at_layer_add appends and extends labels", {
  lyr <- at_layer("l", labels = "a")
  lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 1, 1, label = "a"))
  lyr <- at_layer_add(lyr, at_roi_rect(2, 2, 3, 3, label = "new"))
  expect_identical(at_layer_n(lyr), 2L)
  expect_true("new" %in% lyr$labels)
  expect_true("new" %in% names(lyr$style$colour))
})

test_that("at_layer_add re-mints colliding identifiers", {
  lyr <- at_layer("l", labels = "a")
  r <- at_roi_rect(0, 0, 1, 1, label = "a", id = "dup")
  lyr <- at_layer_add(lyr, r)
  lyr <- at_layer_add(lyr, r)
  ids <- vapply(lyr$rois, `[[`, character(1), "id")
  expect_length(unique(ids), 2L)
})

test_that("at_layer_add does not modify its input", {
  lyr <- at_layer("l", labels = "a")
  snapshot <- lyr
  invisible(at_layer_add(lyr, at_roi_rect(0, 0, 1, 1, label = "a")))
  expect_identical(lyr, snapshot)
})

test_that("at_layer_remove drops the ROI or warns", {
  lyr <- at_layer("l", labels = "a")
  r <- at_roi_rect(0, 0, 1, 1, label = "a", id = "keepme")
  lyr <- at_layer_add(lyr, r)
  lyr2 <- at_layer_remove(lyr, "keepme")
  expect_identical(at_layer_n(lyr2), 0L)
  expect_warning(at_layer_remove(lyr, "nope"), "nothing removed")
})

test_that("at_layer_rois honours the query contract when empty", {
  t <- at_layer_rois(at_layer("l"))
  expect_equal(nrow(t), 0L)
  expect_identical(names(t), names(.empty_roi_tbl()))
})

test_that("at_style rejects a non-character colour", {
  expect_error(at_style(colour = 42), "character vector")
})

test_that("layer print and format produce output", {
  lyr <- at_layer_add(at_layer("l", labels = "a"), at_roi_rect(0, 0, 1, 1, label = "a"))
  expect_output(print(lyr), "annot_layer")
  expect_type(format(lyr), "character")
})

test_that("a single layer colour applies to labels added later (C11)", {
  lyr <- at_layer("l", style = at_style(colour = "#FF0000"))
  lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 1, 1, label = "a"))
  lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 1, 1, label = "b"))
  expect_identical(unname(lyr$style$colour), c("#FF0000", "#FF0000"))
  named <- at_layer("n", style = at_style(colour = c(b = "#00FF00")))
  named <- at_layer_add(named, at_roi_rect(0, 0, 1, 1, label = "a"))
  named <- at_layer_add(named, at_roi_rect(0, 0, 1, 1, label = "b"))
  expect_identical(named$style$colour[["b"]], "#00FF00")
  # Existing assignments never change when a label is added.
  dflt <- at_layer("d", labels = c("x", "y"))
  before <- dflt$style$colour
  dflt <- at_layer_add(dflt, at_roi_rect(0, 0, 1, 1, label = "z"))
  expect_identical(dflt$style$colour[c("x", "y")], before)
})

test_that("a re-minted layer id is unique within the layer after a counter restart", {
  .reset_id_counter()
  l <- at_layer("l")
  for (i in 1:3) l <- at_layer_add(l, at_roi_point(i, i, label = "a"))
  .reset_id_counter()
  l <- at_layer_add(l, at_roi_point(9, 9, label = "a", id = "roi_000000002"))
  ids <- vapply(l$rois, `[[`, character(1), "id")
  expect_false(anyDuplicated(ids) > 0L)
})
