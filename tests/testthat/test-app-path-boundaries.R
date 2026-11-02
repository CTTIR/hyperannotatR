# Synthetic siblings only: no fixture reads outside this temporary tree.
boundary_tree <- function(envir = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = envir)
  root <- file.path(d, "allowed")
  outside <- file.path(d, "outside")
  dir.create(root)
  dir.create(outside)
  withr::local_options(hyperannotatR.app_root = root, .local_envir = envir)
  list(root = root, outside = outside)
}

boundary_link <- function(from, to) {
  if (!isTRUE(file.symlink(from, to))) skip("Symbolic links are unavailable")
}

test_that("folder discovery excludes escaped directory and image symlinks", {
  d <- boundary_tree()
  file.copy(at_example_path("tissue"), file.path(d$outside, "outside.png"))
  boundary_link(d$outside, file.path(d$root, "linked-folder"))
  boundary_link(file.path(d$outside, "outside.png"), file.path(d$root, "linked.png"))
  expect_length(.app_list_images(d$root), 0L)
  expect_length(.app_list_images(d$outside), 0L)
  file.copy(at_example_path("tissue"), file.path(d$root, "inside.png"))
  expect_identical(basename(as.character(.app_list_images(d$root))), "inside.png")
})

test_that("allowed directory links work and cycles do not repeat the queue", {
  d <- boundary_tree()
  images <- file.path(d$root, "images")
  dir.create(images)
  file.copy(at_example_path("tissue"), file.path(images, "inside.png"))
  boundary_link(d$root, file.path(images, "cycle"))
  boundary_link(images, file.path(d$root, "alias"))
  found <- .app_list_images(d$root, max_depth = 12L)
  expect_length(found, 1L)
  expect_identical(normalizePath(as.character(found)), normalizePath(file.path(images, "inside.png")))
  expect_false(attr(found, "truncated"))
  only_link <- file.path(d$root, "only-link")
  dir.create(only_link)
  boundary_link(file.path(images, "inside.png"), file.path(only_link, "alias.png"))
  expect_length(.app_list_images(only_link), 1L)
  withr::local_options(hyperannotatR.app_root = NULL)
  # With the restriction unset, an external source is still a valid local input.
  file.copy(at_example_path("tissue"), file.path(d$outside, "outside.png"))
  boundary_link(d$outside, file.path(only_link, "external"))
  expect_setequal(basename(.app_list_images(only_link)), c("alias.png", "outside.png"))
})

test_that("folder discovery checks ENVI companion payloads and headers", {
  d <- boundary_tree()
  hdr <- at_example_path("cube")
  dat <- sub("\\.hdr$", ".dat", hdr)
  file.copy(hdr, file.path(d$root, "cube.hdr"))
  file.copy(dat, file.path(d$outside, "cube.dat"))
  boundary_link(file.path(d$outside, "cube.dat"), file.path(d$root, "cube.dat"))
  expect_length(.app_list_images(d$root), 0L)
  unlink(file.path(d$root, "cube.dat"))
  file.copy(dat, file.path(d$root, "cube.dat"))
  expect_identical(basename(as.character(.app_list_images(d$root))), "cube.hdr")
  file.copy(hdr, file.path(d$outside, "cube.hdr"))
  unlink(file.path(d$root, "cube.hdr"))
  boundary_link(file.path(d$outside, "cube.hdr"), file.path(d$root, "cube.hdr"))
  expect_length(.app_list_images(d$root), 0L)
})

test_that("folder discovery checks the selected TIVITA profile sidecar", {
  d <- boundary_tree()
  cube <- file.path(d$root, "sample_SpecCube.dat")
  writeBin(as.raw(0), cube)
  sidecar <- file.path(d$outside, "profile.json")
  writeLines("{}", sidecar)
  boundary_link(sidecar, paste0(cube, ".tivita.json"))
  expect_length(.app_list_images(d$root), 0L)
  unlink(paste0(cube, ".tivita.json"))
  file.copy(sidecar, paste0(cube, ".tivita.json"))
  expect_identical(as.character(.app_list_images(d$root)), cube)
})

test_that("a rejected symlink folder preserves annotations and permits recovery", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("shinyjs")
  skip_if_not_installed("htmlwidgets")
  skip_if_not_installed("magick")
  d <- boundary_tree()
  file.copy(at_example_path("tissue"), file.path(d$outside, "outside.png"))
  rejected <- file.path(d$root, "rejected")
  valid <- file.path(d$root, "valid")
  dir.create(rejected)
  dir.create(valid)
  boundary_link(d$outside, file.path(rejected, "external"))
  file.copy(at_example_path("tissue"), file.path(valid, "valid.png"))
  sess <- at_example_session(1)
  sess$autosave <- FALSE
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    event <- function(payload) {
      rv$display_ready <- TRUE
      list(entry_id = rv$entry_id, revision = rv$revision, payload = payload)
    }
    feature <- list(type = "Feature", properties = list(),
                    geometry = list(type = "Point", coordinates = c(2, 3)),
                    target = list(layer = rv$active_layer, label = rv$active_label))
    session$setInputs(`canvas-canvas_created` = event(feature))
    original <- rv$project
    generation <- rv$session_generation
    session$setInputs(`data-load` = event(list(dir = rejected)))
    expect_match(output$`data-msg`, "outside the folder")
    expect_identical(rv$project, original)
    expect_identical(rv$session_generation, generation)
    expect_identical(rv$saved, "unsaved")
    expect_null(rv$recovery_queue)
    session$setInputs(`data-load` = event(list(dir = valid)))
    expect_match(output$`data-msg`, "Loaded 1 image")
    expect_identical(basename(rv$project$image$source), "valid.png")
    session$setInputs(`data-restore` = event(list()))
    expect_identical(at_rois(rv$project), at_rois(original))
    expect_identical(rv$saved, "unsaved")
  })
})

test_that("staged handoffs check inventories and linked directories before reading", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("shinyjs")
  skip_if_not_installed("htmlwidgets")
  skip_if_not_installed("magick")
  d <- boundary_tree()
  rejected <- file.path(d$root, "rejected")
  dir.create(rejected)
  outside <- file.path(d$outside, "integrity.json")
  writeLines('{"format_version":"999.0"}', outside)
  boundary_link(outside, file.path(rejected, "integrity.json"))
  valid <- file.path(d$root, "valid")
  at_export_qupflowr(at_example_project(), valid, formats = "qupath_geojson")
  sess <- at_example_session(1)
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    event <- function(path) {
      rv$display_ready <- TRUE
      list(entry_id = rv$entry_id, revision = rv$revision,
           payload = list(handoff = path))
    }
    original <- rv$project
    # A filename entry point must receive the same preflight as a directory.
    for (path in c(rejected, file.path(rejected, "manifest.json"))) {
      if (!file.exists(path)) writeLines("{}", path)
      session$setInputs(`data-stage` = event(path))
      expect_match(output$`data-stage_msg`, "outside the folder")
      expect_false(grepl("999.0", output$`data-stage_msg`, fixed = TRUE))
      expect_null(rv$staged)
      expect_identical(rv$project, original)
    }
    # Do not let the verifier recursively list an external directory first.
    boundary_link(d$outside, file.path(valid, "external"))
    session$setInputs(`data-stage` = event(valid))
    expect_match(output$`data-stage_msg`, "outside the folder")
    expect_null(rv$staged)
    unlink(file.path(valid, "external"))
    session$setInputs(`data-stage` = event(valid))
    expect_s3_class(rv$staged, "at_staged_patch")
    expect_match(output$`data-stage_msg`, "Staged:")
    expect_identical(rv$project, original)
  })
})

test_that("staged mask imports check external legend sidecars before decoding", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("shinyjs")
  skip_if_not_installed("htmlwidgets")
  skip_if_not_installed("magick")
  d <- boundary_tree()
  mask <- at_mask(at_roi_rect(0, 0, 1, 1, label = "region"),
                  dims = c(2, 2), type = "labelled")
  path <- file.path(d$root, "mask.npy")
  at_write_npy(mask, path)
  side <- paste0(path, ".legend.json")
  outside <- file.path(d$outside, "legend.json")
  expect_true(file.rename(side, outside))
  boundary_link(outside, side)
  sess <- at_example_session(1)
  shiny::testServer(.app_server(sess), {
    session$flushReact()
    rv$display_ready <- TRUE
    original <- rv$project
    session$setInputs(`data-stage` = list(entry_id = rv$entry_id,
      revision = rv$revision, payload = list(handoff = path)))
    expect_match(output$`data-stage_msg`, "outside the folder")
    expect_null(rv$staged)
    expect_identical(rv$project, original)
  })
})
