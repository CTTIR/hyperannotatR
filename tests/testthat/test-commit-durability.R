commit_memory_fixture <- function() {
  pixels <- array(seq_len(12L), c(3L, 4L, 1L))
  image <- new_annot_image(
    "memory:commit-fixture", "raster", c(4L, 3L), 1L,
    list(c(4L, 3L)), 1L, handle = list(data = pixels)
  )
  project <- at_project(image, at_layer("regions"))
  partner <- at_layer_add(at_layer("regions"),
    at_roi_rect(0, 0, 2, 2, label = "region", id = "partner-1"))
  list(project = project, partner = partner, pixels = pixels)
}

commit_file_bytes <- function(path) readBin(path, "raw", n = file.size(path))

test_that("a partner commit retains the pixels of an in-memory project", {
  f <- commit_memory_fixture()
  path <- file.path(withr::local_tempdir(), "project.rds")
  receipt <- at_commit_qupflowr(at_stage_qupflowr(f$project, f$partner),
                               destination = path)
  reopened <- at_load_project(path)
  expect_identical(reopened$image$handle$data, f$pixels)
  expect_identical(at_tile(reopened$image), at_tile(f$project$image))
  expect_identical(at_annotation_revision(reopened), receipt$new_revision)
})

test_that("an unusable receipt path leaves the project unchanged and retryable", {
  f <- commit_memory_fixture()
  path <- file.path(withr::local_tempdir(), "project.rds")
  at_save_project(f$project, path)
  patch <- at_stage_qupflowr(path, f$partner)
  previous <- commit_file_bytes(path)
  side <- paste0(path, ".commit.json")
  dir.create(side)
  err <- tryCatch(at_commit_qupflowr(patch, overwrite = TRUE), error = identity)
  expect_s3_class(err, "at_io_error")
  expect_identical(err$code, "INVALID_PATH")
  expect_identical(commit_file_bytes(path), previous)
  expect_identical(at_annotation_revision(at_load_project(path)),
                   patch$base_revision)
  expect_true(dir.exists(side))
  unlink(side, recursive = TRUE)
  receipt <- at_commit_qupflowr(patch, overwrite = TRUE)
  expect_false(receipt$replayed)
  expect_identical(at_annotation_revision(at_load_project(path)),
                   receipt$new_revision)
})

test_that("failure to publish the receipt restores both existing files", {
  f <- commit_memory_fixture()
  root <- normalizePath(withr::local_tempdir(), winslash = "/")
  path <- file.path(root, "project.rds")
  at_save_project(f$project, path)
  side <- paste0(path, ".commit.json")
  writeLines('{"previous":"receipt"}', side)
  previous <- lapply(c(path, side), commit_file_bytes)
  patch <- at_stage_qupflowr(path, f$partner)
  local({
    local_mocked_bindings(.rename_path = function(from, to) {
      publishing <- grepl("^[.](export-stage|hyperannotatR)-", basename(from))
      if (identical(to, side) && publishing) return(FALSE)
      file.rename(from, to)
    })
    err <- tryCatch(at_commit_qupflowr(patch, overwrite = TRUE), error = identity)
    expect_s3_class(err, "at_io_error")
    expect_identical(err$code, "WRITE_FAILED")
  })
  expect_identical(lapply(c(path, side), commit_file_bytes), previous)
  expect_setequal(list.files(root, all.files = TRUE, no.. = TRUE),
                  c("project.rds", "project.rds.commit.json"))
  receipt <- at_commit_qupflowr(patch, overwrite = TRUE)
  expect_false(receipt$replayed)
  expect_identical(at_annotation_revision(at_load_project(path)),
                   receipt$new_revision)
  expect_identical(jsonlite::read_json(side)$new_revision, receipt$new_revision)
})

test_that("durable replay refuses a project edited since the recorded commit", {
  f <- commit_memory_fixture()
  root <- withr::local_tempdir()
  path <- file.path(root, "project.rds")
  patch <- at_stage_qupflowr(f$project, f$partner)
  receipt <- at_commit_qupflowr(patch, destination = path)
  changed <- at_add_roi(receipt$project, "regions",
    at_roi_rect(2, 0, 3, 1, label = "later", id = "later-1"))
  at_save_project(changed, path, overwrite = TRUE)
  previous <- lapply(c(path, paste0(path, ".commit.json")), commit_file_bytes)
  patch_path <- file.path(root, "patch.rds")
  saveRDS(patch, patch_path)
  result <- audit_fresh('{
    patch <- readRDS(args$patch)
    result <- tryCatch(at_commit_qupflowr(patch, destination = args$path,
                                         overwrite = TRUE), error = identity)
    list(error = inherits(result, "at_conflict_error"), code = result$code,
         details = result$details)
  }', list(patch = patch_path, path = path))
  expect_true(result$error)
  expect_identical(result$code, "REVISION_CONFLICT")
  expect_identical(result$details$expected, receipt$new_revision)
  expect_identical(result$details$actual, at_annotation_revision(changed))
  expect_identical(lapply(c(path, paste0(path, ".commit.json")),
                         commit_file_bytes), previous)
})

test_that("cached replay rechecks the saved project and destination", {
  f <- commit_memory_fixture()
  root <- normalizePath(withr::local_tempdir(), winslash = "/")
  path <- file.path(root, "project.rds")
  patch <- at_stage_qupflowr(f$project, f$partner)
  receipt <- at_commit_qupflowr(patch, destination = path)
  # Canonical aliases still address the same commit.
  alias <- file.path(root, ".", "project.rds")
  expect_true(at_commit_qupflowr(patch, destination = alias)$replayed)
  other <- file.path(root, "different.rds")
  err <- tryCatch(at_commit_qupflowr(patch, destination = other), error = identity)
  expect_s3_class(err, "at_conflict_error")
  expect_identical(err$code, "IDEMPOTENCY_CONFLICT")
  expect_false(file.exists(other))
  err <- tryCatch(at_commit_qupflowr(patch), error = identity)
  expect_identical(err$code, "IDEMPOTENCY_CONFLICT")
  changed <- at_add_roi(receipt$project, "regions",
    at_roi_rect(2, 0, 3, 1, label = "later", id = "later-1"))
  at_save_project(changed, path, overwrite = TRUE)
  previous <- lapply(c(path, paste0(path, ".commit.json")), commit_file_bytes)
  err <- tryCatch(at_commit_qupflowr(patch, destination = path), error = identity)
  expect_s3_class(err, "at_conflict_error")
  expect_identical(err$code, "REVISION_CONFLICT")
  expect_identical(err$details$expected, receipt$new_revision)
  expect_identical(err$details$actual, at_annotation_revision(changed))
  expect_identical(lapply(c(path, paste0(path, ".commit.json")),
                         commit_file_bytes), previous)
})
