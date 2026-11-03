test_that("OME core metadata supports accessors that inspect their call name", {
  skip_if_not_installed("RBioFormats")
  skip_if_not_installed("xml2")
  actual <- RBioFormats::coreMetadata
  local_mocked_bindings(coreMetadata = function(x, ...) {
    # RBioFormats 1.2.0 uses this name as a metadata-list key. A qualified
    # call supplies a three-element vector instead of "coreMetadata".
    caller <- as.character(sys.call()[[1L]])
    if (!identical(caller, "coreMetadata")) stop("ambiguous metadata accessor")
    coreMetadata <- actual
    coreMetadata(x, ...)
  }, .package = "RBioFormats")
  path <- test_path("fixtures", "readers", "images", "reference-pyramid.ome.tif")
  expect_true(file.exists(path))
  image <- at_read_image(path, backend = "ometiff")
  expect_s3_class(image, "annot_image")
  expect_true(all(image$dims > 0))
  expect_gt(image$n_levels, 1L)
})
