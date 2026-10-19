test_that(".check_string accepts a string and rejects non-strings", {
  expect_invisible(.check_string("a"))
  expect_error(.check_string(1), "must be a single string")
  expect_error(.check_string(c("a", "b")), "must be a single string")
  expect_error(.check_string(NA_character_), "must be a single string")
  expect_invisible(.check_string(NULL, allow_null = TRUE))
})

test_that(".check_flag requires a single TRUE/FALSE", {
  expect_invisible(.check_flag(TRUE))
  expect_error(.check_flag(NA), "TRUE")
  expect_error(.check_flag(c(TRUE, FALSE)), "TRUE")
  expect_error(.check_flag("yes"), "TRUE")
})

test_that(".check_number enforces finiteness and bounds", {
  expect_invisible(.check_number(1.5))
  expect_error(.check_number(Inf), "finite")
  expect_error(.check_number(NA_real_), "finite")
  expect_error(.check_number(5, max = 4), "range")
  expect_error(.check_number(-1, min = 0), "range")
})

test_that(".check_count requires a non-negative whole number", {
  expect_identical(.check_count(3), 3L)
  expect_error(.check_count(1.5), "whole number")
  expect_error(.check_count(-1), "at least")
})

test_that(".check_choice matches one of the allowed values", {
  expect_identical(.check_choice(c("a", "b"), c("a", "b"), default = TRUE), "a")
  expect_identical(.check_choice("b", c("a", "b")), "b")
  expect_error(.check_choice("z", c("a", "b")), "must be one of")
})

test_that(".check_file and .check_dir validate existence", {
  f <- withr::local_tempfile()
  writeLines("x", f)
  expect_invisible(.check_file(f))
  expect_error(.check_file(tempfile()), "existing file")
  expect_invisible(.check_dir(dirname(f)))
  expect_error(.check_dir(tempfile()), "existing directory")
})

test_that(".check_class and domain checkers dispatch on class", {
  expect_error(.check_image(1), "annot_image")
  expect_error(.check_roi(1), "annot_roi")
  expect_error(.check_layer(1), "annot_layer")
  expect_error(.check_project(1), "annot_project")
})

test_that(".empty_roi_tbl has the contracted structure", {
  t <- .empty_roi_tbl()
  expect_s3_class(t, "tbl_df")
  expect_equal(nrow(t), 0L)
  expect_identical(
    names(t),
    c("roi_id", "layer", "label", "geom_type", "level", "source_level", "area_px",
      "centroid_x", "centroid_y", "n_vertices", "created", "modified",
      "author", "source", "geometry")
  )
  expect_type(t$source_level, "integer")
  expect_true(inherits(t$geometry, "sfc"))
})

test_that(".resolve_palette cycles Okabe-Ito and honours names", {
  p <- .resolve_palette(c("a", "b", "c"))
  expect_named(p, c("a", "b", "c"))
  expect_identical(unname(p[1]), "#999999")
  p2 <- .resolve_palette(c("a", "b"), c(a = "#000000"))
  expect_identical(unname(p2["a"]), "#000000")
  expect_length(.resolve_palette(character()), 0L)
})

test_that(".new_id is unique and counter resets deterministically", {
  .reset_id_counter()
  expect_identical(.new_id("roi"), "roi_000000001")
  expect_identical(.new_id("roi"), "roi_000000002")
  .reset_id_counter()
  expect_identical(.new_id("roi"), "roi_000000001")
})

test_that(".check_choice takes an omitted default but rejects explicit vectors", {
  expect_error(.check_choice(c("b", "a", "b"), c("a", "b")), "must be one of")
  expect_error(.check_choice(c("b", "a"), c("a", "b")), "explicit vectors")
  # Omission is detected in the caller's frame, so callers need not pass
  # `default = missing(arg)` themselves.
  f <- function(type = c("labelled", "binary")) .check_choice(type, c("labelled", "binary"))
  expect_identical(f(), "labelled")
  expect_identical(f("binary"), "binary")
  expect_error(f(c("labelled", "binary")), "explicit vectors")
  # A default listed in another order than the choices still means its first.
  g <- function(type = c("binary", "labelled")) .check_choice(type, c("labelled", "binary"))
  expect_identical(g(), "binary")
  # Numeric choices take whole numbers of either type and return the choice.
  h <- function(bits = c(16L, 8L)) .check_choice(bits, c(16L, 8L))
  expect_identical(h(), 16L)
  expect_identical(h(8), 8L)
  expect_error(h(8.5), "must be one of")
  expect_error(.check_choice(c("a", "b"), c("a", "b"), default = FALSE), "must be one of")
})

test_that(".check_count gives a typed error for values beyond the integer range", {
  expect_error(.check_count(3e9), "too large")
  expect_error(.check_count(3e9), class = "at_validation_error")
})
