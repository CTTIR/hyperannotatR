test_that("the loaded version is the version DESCRIPTION declares", {
  # Compare against DESCRIPTION rather than a literal, so a version bump does
  # not fail the suite. Under R CMD check the source DESCRIPTION is not
  # reachable from the test directory; the installed one is then authoritative.
  desc <- testthat::test_path("..", "..", "DESCRIPTION")
  declared <- if (file.exists(desc)) {
    unname(read.dcf(desc, fields = "Version")[1, "Version"])
  } else {
    utils::packageDescription("hyperannotatR", fields = "Version")
  }
  expect_match(declared, "^[0-9]+\\.[0-9]+\\.[0-9]+(\\.[0-9]+)?$")
  expect_identical(as.character(utils::packageVersion("hyperannotatR")), declared)
})

test_that("package namespace can be loaded", {
  expect_true(requireNamespace("hyperannotatR", quietly = TRUE))
})
