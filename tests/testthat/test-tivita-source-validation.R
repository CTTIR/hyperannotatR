# Tiny independent fixture: x, then y, then band, with no header.
reader_profile_fixture <- function(dir, sidecar = TRUE, lower_priority = FALSE) {
  path <- file.path(dir, "tiny_SpecCube.dat")
  con <- file(path, "wb")
  for (x in 1:3) for (y in 1:2) for (b in 1:2) {
    writeBin(as.double(100 * b + 10 * y + x), con, size = 4, endian = "big")
  }
  close(con)
  doc <- list(profile_version = "1.0", name = "tiny", width = 3L,
              height = 2L, bands = 2L, header_values = 0L, value_bytes = 4L,
              endian = "big", axis_order = "x,y,band", wavelengths = c(500, 600),
              wavelength_unit = "nm", value_unit = "raw")
  side <- if (lower_priority) sub("\\.dat$", ".tivita.json", path) else paste0(path, ".tivita.json")
  if (sidecar) jsonlite::write_json(doc, side, auto_unbox = TRUE)
  list(path = path, side = side, doc = doc)
}

reader_error_code <- function(expr) tryCatch({ force(expr); NULL }, error = function(e) e$code)

test_that("TIVITA sidecar changes cannot reinterpret saved or closed pixels", {
  for (change in c("modified", "removed", "higher_priority")) {
    f <- reader_profile_fixture(withr::local_tempdir(), lower_priority = TRUE)
    img <- at_read_image(f$path)
    expected <- at_tile(img)
    expect_identical(expected[2, 3, ], c(123, 223))
    project <- at_project(img)
    saved <- tempfile(fileext = ".rds")
    withr::defer(unlink(saved))
    at_save_project(project, saved)
    unchanged <- at_load_project(saved)
    expect_identical(at_tile(unchanged$image), expected)
    if (change == "modified") {
      f$doc$endian <- "little"
      jsonlite::write_json(f$doc, f$side, auto_unbox = TRUE)
    } else if (change == "removed") {
      unlink(f$side)
    } else {
      f$doc$endian <- "little"
      jsonlite::write_json(f$doc, paste0(f$path, ".tivita.json"), auto_unbox = TRUE)
    }
    status <- if (change == "removed") "missing" else "changed"
    code <- if (change == "removed") "IMAGE_UNAVAILABLE" else "IMAGE_CHANGED"
    expect_identical(at_inspect_source(img)$status, status, info = change)
    expect_identical(reader_error_code(at_tile(img)), code, info = change)
    expect_identical(reader_error_code(at_tile(at_close_image(img))), code, info = change)
    loaded <- at_load_project(saved)
    expect_identical(loaded$layers, project$layers)
    expect_null(loaded$image$handle)
    expect_identical(reader_error_code(at_tile(loaded$image)), code, info = change)
  }
})

test_that("default TIVITA reads detect newly introduced sidecars", {
  # Use the normal constructor with a small default to exercise discovery
  # without allocating a 640 x 480 x 100 cube.
  constructor <- at_tivita_profile
  small_default <- function(...) constructor(name = "tiny", width = 3L,
    height = 2L, bands = 2L, header_values = 0L, wavelengths = c(500, 600),
    value_unit = "raw")
  local_mocked_bindings(at_tivita_profile = small_default)
  f <- reader_profile_fixture(withr::local_tempdir(), sidecar = FALSE)
  img <- at_read_image(f$path)
  expect_identical(img$meta$profile_source, "default_profile")
  expect_identical(at_tile(at_close_image(img))[2, 3, ], c(123, 223))
  jsonlite::write_json(f$doc, f$side, auto_unbox = TRUE)
  expect_identical(at_inspect_source(img)$status, "changed")
  expect_identical(reader_error_code(at_tile(at_close_image(img))), "IMAGE_CHANGED")
})

test_that("explicit TIVITA profiles ignore incidental sidecars", {
  f <- reader_profile_fixture(withr::local_tempdir())
  profile <- at_tivita_profile("tiny", width = 3, height = 2, bands = 2,
    header_values = 0, wavelengths = c(500, 600), value_unit = "raw")
  img <- at_read_image(f$path, profile = profile)
  unlink(f$side)
  expect_identical(at_inspect_source(img)$status, "available")
  expect_identical(at_tile(at_close_image(img))[2, 3, ], c(123, 223))
})

test_that("legacy sidecar descriptors preserve annotations without guessing pixels", {
  f <- reader_profile_fixture(withr::local_tempdir())
  img <- at_read_image(f$path)
  # Older releases recorded only the payload, losing sidecar provenance.
  img$source_descriptor$files <- img$source_descriptor$files["payload"]
  p <- at_project(at_close_image(img))
  saved <- tempfile(fileext = ".rds")
  withr::defer(unlink(saved))
  at_save_project(p, saved)
  loaded <- at_load_project(saved)
  expect_identical(loaded$layers, p$layers)
  expect_identical(at_inspect_source(loaded)$status, "unresolved")
  expect_identical(reader_error_code(at_tile(loaded$image)), "IMAGE_UNAVAILABLE")
  relinked <- at_relink_source(loaded, f$path)
  expect_identical(at_tile(relinked$image)[2, 3, ], c(123, 223))
})

test_that("scientific band requests are validated before integer conversion", {
  img <- new_annot_image("memory", "envi", c(1L, 1L), 1L,
    list(c(1L, 1L)), 2L, wavelengths = c(500, 600), wavelength_unit = "nm",
    handle = list(data = array(c(11, 22), c(1, 1, 2))))
  for (bands in list(1.9, "1", TRUE, factor("1"), 1 + 1i, Inf, NA_real_)) {
    expect_identical(reader_error_code(at_band_view(img, "single", bands = bands)),
                     "BAND_OUT_OF_RANGE")
  }
  expect_identical(as.numeric(at_band_view(img, "single", bands = 2)), 22)
  for (bound in c(NA_real_, NaN, Inf, -Inf)) {
    expect_identical(reader_error_code(at_band_view(img, "wavelength_window_mean",
      params = list(wavelength_min = bound, wavelength_max = 600))), "VALIDATION_FAILED")
  }
})

test_that("calibration references cannot silently coerce or contain nonfinite values", {
  invalid <- list(factor("1000"), "1000", TRUE, 1000 + 1i, Inf, -Inf, NA_real_, NaN,
                  numeric(), list(1000), matrix(1000, 1, 1))
  for (reference in invalid) for (field in c("white", "dark")) {
    calibration <- list(white = 1000, dark = 0)
    calibration[[field]] <- reference
    expect_identical(reader_error_code(at_convert_values(500, from = "raw",
      to = "reflectance", calibration = calibration)), "CALIBRATION_INVALID")
  }
  expect_identical(reader_error_code(at_convert_values(500, from = "raw",
    to = "reflectance", calibration = 1000)), "CALIBRATION_INVALID")
  out <- at_convert_values(c(500, 500), from = "raw", to = "reflectance",
    calibration = list(white = c(1000L, 500L), dark = c(0L, 500L)))
  expect_identical(as.numeric(out), c(0.5, NA_real_))
})

test_that("legacy TIVITA profile ambiguity requires deliberate relinking", {
  f <- reader_profile_fixture(withr::local_tempdir())
  img <- at_read_image(f$path)
  img$meta$profile_digest <- NULL
  expect_identical(at_inspect_source(img)$status, "unresolved")
  err <- tryCatch(at_tile(at_close_image(img)), error = identity)
  expect_identical(if (inherits(err, "error")) err$code else NULL, "IMAGE_UNAVAILABLE")
  expect_identical(as.numeric(at_tile(at_relink_source(img, f$path))),
    c(111, 121, 112, 122, 113, 123, 211, 221, 212, 222, 213, 223))
  img$meta$profile_source <- NULL
  expect_identical(at_inspect_source(img)$status, "unresolved")
})
