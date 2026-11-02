test_that("mask budgets apply before every rasterisation mode and empty masks", {
  withr::local_options(hyperannotatR.max_read_bytes = 127)
  roi <- at_roi_rect(0, 0, 1, 1, label = "a")
  layer <- at_layer_add(at_layer("regions"), roi)
  layer <- at_layer_add(layer, at_roi_rect(1, 1, 2, 2, label = "b"))
  # These sentinels also keep the baseline run safe: no native rasterisation
  # is needed to demonstrate that the budget was previously bypassed.
  local_mocked_bindings(
    .rasterize_batch = function(...) stop("rasterisation reached"),
    .rasterize_per_roi = function(...) stop("rasterisation reached")
  )
  for (engine in c("stars", "terra")) for (touches in c(FALSE, TRUE)) {
    for (type in c("binary", "labelled", "multiclass")) {
      err <- tryCatch(at_mask(layer, dims = c(2, 2), type = type,
                               engine = engine, touches = touches), error = identity)
      expect_s3_class(err, "at_limit_error")
      expect_identical(err$code, "READ_BUDGET_EXCEEDED")
      expect_identical(err$details$requested_bytes, 128)
      expect_identical(err$details$limit_bytes, 127)
    }
  }
  for (x in list(roi, at_layer("empty"))) {
    err <- tryCatch(at_mask(x, dims = c(2, 2)), error = identity)
    expect_identical(err$code, "READ_BUDGET_EXCEEDED")
  }
})

test_that("mask dimensions fail before unsafe coercion or large allocation", {
  roi <- at_roi_rect(0, 0, 1, 1, label = "region")
  # In unfixed code, even huge requests stop here before matrix allocation.
  local_mocked_bindings(
    .rasterize_per_roi = function(...) stop("rasterisation reached")
  )
  for (dims in list(c(NA_real_, 2), c(Inf, 2), c(0, 2), c(-1, 2))) {
    err <- suppressWarnings(tryCatch(at_mask(roi, dims = dims), error = identity))
    expect_identical(err$code, "LAYOUT_INVALID")
  }
  for (dims in list(c(2^31, 1), c(50000, 50000))) {
    err <- suppressWarnings(tryCatch(at_mask(roi, dims = dims), error = identity))
    expect_s3_class(err, "at_limit_error")
    expect_identical(err$code, "MASK_TOO_LARGE")
  }
})

test_that("trusted mask budgets retain fractional extents and exact pixels", {
  roi <- at_roi_rect(0, 0, 2, 2, label = "region")
  withr::local_options(hyperannotatR.max_read_bytes = 32 * 12)
  mask <- at_mask(roi, dims = c(3.1, 2.1), type = "labelled")
  expected <- matrix(0L, 3L, 4L)
  expected[1:2, 1:2] <- 1L
  expect_identical(as.matrix(mask), expected)
  expect_identical(attr(mask, "dims"), c(4L, 3L))
})
