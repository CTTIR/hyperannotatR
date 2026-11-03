skip_if_not_installed("png")
skip_if_not_installed("magick")

test_that("control staging confines import companions to its own negotiated root", {
  d <- withr::local_tempdir()
  root <- file.path(d, "allowed")
  outside <- file.path(d, "outside")
  dir.create(root)
  dir.create(outside)
  # The app option belongs to another caller and must neither govern this
  # control instance nor be mutated while checking its paths.
  withr::local_options(hyperannotatR.app_root = outside)
  image <- file.path(root, "image.png")
  png::writePNG(matrix(0.5, 4, 4), image)
  sess <- at_session(image, out_dir = file.path(d, "saved"), autosave = FALSE)
  h <- at_control_start(sess, root = root, serve = FALSE)
  withr::defer(at_control_stop(h))
  bad <- file.path(root, "bad")
  dir.create(bad)
  writeLines('{"format_version":"999.0"}', file.path(outside, "integrity.json"))
  if (!isTRUE(portable_test_link(file.path(outside, "integrity.json"),
                          file.path(bad, "integrity.json")))) {
    skip("Symbolic links are unavailable")
  }
  writeLines("{}", file.path(bad, "manifest.json"))
  mask <- at_mask(at_roi_rect(0, 0, 1, 1, label = "region"),
                  dims = c(2, 2), type = "labelled")
  path <- file.path(root, "mask.npy")
  at_write_npy(mask, path)
  side <- paste0(path, ".legend.json")
  expect_true(file.rename(side, file.path(outside, "legend.json")))
  expect_true(portable_test_link(file.path(outside, "legend.json"), side))
  partner <- at_project(at_read_image(image), at_layer("regions", labels = "region"))
  partner <- at_add_roi(partner, "regions",
    at_roi_rect(0, 0, 2, 2, label = "region", id = "reviewed-1"))
  at_export_qupflowr(partner, file.path(root, "good"), formats = "qupath_geojson")
  before <- at_control_state(h)
  stage <- function(ref) at_control_command(h, list(
    operation = "annotations.stage", payload = list(payload_ref = ref),
    expected_revision = at_control_state(h)$state_revision
  ))
  for (ref in c("bad", "bad/manifest.json", "mask.npy")) {
    err <- tryCatch(stage(ref), error = identity)
    expect_s3_class(err, "at_io_error")
    expect_identical(err$code, "PATH_OUTSIDE_ROOT", info = ref)
    state <- at_control_state(h)
    expect_identical(state$state_revision, before$state_revision)
    expect_identical(state$current$rois, before$current$rois)
    expect_null(.control_hub(h)$staged)
    expect_identical(getOption("hyperannotatR.app_root"), outside)
  }
  valid <- stage("good")
  expect_identical(valid$summary$create, 1L)
  expect_identical(at_control_state(h)$annotation_status, "staged")
  expect_identical(at_control_state(h)$current$rois, before$current$rois)
  expect_identical(getOption("hyperannotatR.app_root"), outside)
})

test_that("control session loads preflight every image and optional handoff", {
  d <- withr::local_tempdir()
  root <- file.path(d, "allowed")
  outside <- file.path(d, "outside")
  dir.create(root)
  dir.create(outside)
  withr::local_options(hyperannotatR.app_root = outside)
  png::writePNG(matrix(0.5, 4, 4), file.path(root, "image.png"))
  sess <- at_session(file.path(root, "image.png"), out_dir = file.path(d, "saved"))
  h <- at_control_start(sess, root = root, serve = FALSE)
  withr::defer(at_control_stop(h))
  writeLines(c("ENVI", "samples = 2", "lines = 1", "bands = 1", "data type = 4",
               "interleave = bsq", "byte order = 0"), file.path(root, "cube.hdr"))
  writeBin(c(11, 22), file.path(outside, "cube.dat"), size = 4, endian = "little")
  if (!isTRUE(portable_test_link(file.path(outside, "cube.dat"), file.path(root, "cube.dat")))) {
    skip("Symbolic links are unavailable")
  }
  cube <- file.path(root, "tiny_SpecCube.dat")
  writeBin(c(11, 22), cube, size = 4, endian = "big")
  profile <- list(profile_version = "1.0", name = "tiny", width = 1L,
    height = 1L, bands = 2L, header_values = 0L, value_bytes = 4L,
    endian = "big", axis_order = "x,y,band", wavelengths = c(500, 600),
    wavelength_unit = "nm", value_unit = "raw")
  jsonlite::write_json(profile, file.path(outside, "profile.json"), auto_unbox = TRUE)
  expect_true(portable_test_link(file.path(outside, "profile.json"), paste0(cube, ".tivita.json")))
  bad <- file.path(root, "bad")
  dir.create(bad)
  writeLines('{"format_version":"999.0"}', file.path(outside, "integrity.json"))
  expect_true(portable_test_link(file.path(outside, "integrity.json"), file.path(bad, "integrity.json")))
  load <- function(payload) at_control_command(h, list(operation = "session.load",
    payload = payload, expected_revision = at_control_state(h)$state_revision))
  for (payload in list(list(images = list("image.png", "cube.hdr")),
                       list(images = list("tiny_SpecCube.dat")),
                       list(images = list("image.png"), handoff = "bad"))) {
    before <- at_control_state(h)
    old_session <- .control_hub(h)$session
    err <- tryCatch(load(payload), error = identity)
    expect_s3_class(err, "at_io_error")
    expect_identical(err$code, "PATH_OUTSIDE_ROOT")
    expect_identical(.control_hub(h)$session, old_session)
    expect_identical(at_control_state(h)$state_revision, before$state_revision)
    expect_identical(getOption("hyperannotatR.app_root"), outside)
  }
  # Moving the payload inside the root makes the same in-root link valid.
  fs::link_delete(file.path(root, "cube.dat"))
  expect_true(file.copy(file.path(outside, "cube.dat"), file.path(root, "payload.bin")))
  expect_true(portable_test_link(file.path(root, "payload.bin"), file.path(root, "cube.dat")))
  result <- load(list(images = list("cube.hdr")))
  expect_identical(result$n_images, 1L)
  expect_identical(as.numeric(at_tile(at_current(.control_hub(h)$session)$image)), c(11, 22))
  expect_identical(getOption("hyperannotatR.app_root"), outside)
})
