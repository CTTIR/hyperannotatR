skip_if_not_installed("png")

test_that("control commit keys are scoped to each instance and still replay", {
  root <- withr::local_tempdir()
  handles <- list()
  withr::defer(for (h in handles) at_control_stop(h))
  for (i in 1:2) {
    image <- file.path(root, paste0("image", i, ".png"))
    png::writePNG(matrix(i / 2, 4L, 4L), image)
    handles[[i]] <- at_control_start(
      at_session(image, out_dir = file.path(root, paste0("session", i))),
      serve = FALSE
    )
  }
  project <- .hub_project(.control_hub(handles[[1]]))
  project$layers$regions <- at_layer_add(at_layer("regions"),
    at_roi_rect(0, 0, 2, 2, label = "region", id = "partner-1"))
  path <- file.path(root, "patch.geojson")
  at_write_qupath(project, path)
  features <- jsonlite::read_json(path)$features
  stages <- lapply(handles, function(h) at_control_command(h, list(
    operation = "annotations.stage", payload = list(features = features),
    expected_revision = at_control_state(h)$state_revision
  )))
  # The same content intentionally yields equal patch digests for two images.
  digests <- vapply(handles, function(h) .control_hub(h)$staged$patch_digest,
                    character(1))
  expect_identical(digests[1], digests[2])
  for (i in 1:2) {
    h <- handles[[i]]
    command <- list(
      operation = "annotations.commit",
      payload = list(patch_id = stages[[i]]$patch_id),
      expected_revision = at_control_state(h)$state_revision,
      idempotency_key = "client-commit-1"
    )
    receipt <- at_control_command(h, command)
    expect_identical(receipt$patch_id, stages[[i]]$patch_id)
    expect_identical(basename(.hub_project(.control_hub(h))$image$source),
                     paste0("image", i, ".png"))
    revision <- at_control_state(h)$state_revision
    replay <- at_control_command(h, command)
    expect_true(attr(replay, "response")$replayed)
    expect_identical(replay$patch_id, receipt$patch_id)
    expect_identical(replay$new_revision, receipt$new_revision)
    expect_identical(at_control_state(h)$state_revision, revision)
  }
  # The wire contract permits 128-character keys. Internal namespacing must
  # not make an otherwise valid client key exceed the direct commit limit.
  h <- handles[[1]]
  staged <- at_control_command(h, list(
    operation = "annotations.stage", payload = list(features = features),
    expected_revision = at_control_state(h)$state_revision
  ))
  receipt <- at_control_command(h, list(
    operation = "annotations.commit", payload = list(patch_id = staged$patch_id),
    expected_revision = at_control_state(h)$state_revision,
    idempotency_key = strrep("k", 128L)
  ))
  expect_identical(receipt$patch_id, staged$patch_id)
})
