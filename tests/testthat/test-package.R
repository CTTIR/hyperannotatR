test_that("hyperannotatR is installed with the expected version", {
  expect_identical(
    as.character(utils::packageVersion("hyperannotatR")),
    "0.2.0"
  )
})

test_that("package namespace can be loaded", {
  expect_true(requireNamespace("hyperannotatR", quietly = TRUE))
})
