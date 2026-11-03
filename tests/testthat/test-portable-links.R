test_that("handoff and export link guards work with Windows readlink semantics", {
  d <- normalizePath(withr::local_tempdir(), winslash = "/")
  root <- file.path(d, "root")
  dir.create(root)
  target <- file.path(root, "target.json")
  writeLines("preserved", target)
  links <- file.path(root, c("linked.json", "dangling.json", "folder"))
  portable_test_link(target, links[[1L]])
  portable_test_link(file.path(d, "missing"), links[[2L]])
  portable_test_link(d, links[[3L]])
  withr::defer(fs::link_delete(links[fs::is_link(links)]))
  local_mocked_bindings(Sys.readlink = function(paths) rep("", length(paths)),
                        .package = "base")
  expect_true(all(.is_symlink(links)))
  expect_false(.is_symlink(file.path(root, "absent")))
  expect_true(.export_exists(links[[2L]]))
  expect_error(.export_preflight(root, links[[1L]]), "Symlink")
  expect_error(.export_bundle(links[[1L]], function(...) stop("writer called"),
                              overwrite = TRUE), "Symlink")
  # An internal link is also forbidden in an integrity-inventoried handoff.
  fs::link_delete(links[2:3])
  err <- tryCatch(.import_path_preflight(root, root), error = identity)
  expect_s3_class(err, "at_error")
  expect_identical(err$code, "INTEGRITY_SYMLINK")
  expect_identical(readLines(target), "preserved")
})

test_that("ENVI reads use resolved companion metadata and retain retarget checks", {
  d <- normalizePath(withr::local_tempdir(), winslash = "/")
  hdr <- file.path(d, "cube.hdr")
  dat <- file.path(d, "cube.dat")
  target <- file.path(d, "payload.bin")
  writeLines(c("ENVI", "samples = 2", "lines = 1", "bands = 1",
               "data type = 4", "interleave = bsq", "byte order = 0"), hdr)
  writeBin(c(11, 22), target, size = 4, endian = "little")
  portable_test_link(target, dat)
  withr::defer(fs::link_delete(dat[fs::is_link(dat)]))
  real_info <- base::file.info
  local_mocked_bindings(file.info = function(..., extra_cols = TRUE) {
    result <- real_info(..., extra_cols = extra_cols)
    paths <- unlist(list(...), use.names = FALSE)
    result$size[fs::is_link(paths)] <- 0
    result
  }, .package = "base")
  img <- at_read_image(hdr)
  expect_identical(as.numeric(at_tile(img)), c(11, 22))
  expect_identical(.source_signature(dat), .source_signature(target))
  expect_identical(at_inspect_source(img)$status, "available")
})

test_that("link fixtures distinguish files, dangling files and directories", {
  d <- normalizePath(withr::local_tempdir(), winslash = "/")
  target <- file.path(d, "target.txt")
  writeLines("real file payload", target)
  file_link <- file.path(d, "file-link")
  missing_link <- file.path(d, "missing-link")
  dir_link <- file.path(d, "dir-link")
  portable_test_link(target, file_link)
  portable_test_link(file.path(d, "absent.txt"), missing_link)
  portable_test_link(d, dir_link)
  expect_true(all(.is_symlink(c(file_link, missing_link, dir_link))))
  expect_false(dir.exists(file_link))
  expect_identical(readLines(file_link), "real file payload")
  expect_identical(normalizePath(file_link), normalizePath(target))
  expect_false(file.exists(missing_link))
  expect_false(dir.exists(missing_link))
  expect_true(dir.exists(dir_link))
})

test_that("Windows junctions cannot become export descendants", {
  skip_if_not(.Platform$OS.type == "windows")
  d <- normalizePath(withr::local_tempdir(), winslash = "/")
  root <- file.path(d, "root")
  outside <- file.path(d, "outside")
  dir.create(root)
  dir.create(outside)
  junction <- file.path(root, "linked")
  expect_true(Sys.junction(outside, junction))
  withr::defer(fs::link_delete(junction[fs::is_link(junction)]))
  expect_true(.is_symlink(junction))
  expect_error(.export_preflight(root, file.path(junction, "new.json")),
               "Symlink")
  expect_length(list.files(outside, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("the independent digest oracle works without the newer tools API", {
  skip_if_not_installed("openssl")
  actual <- base::getNamespaceExports
  local_mocked_bindings(getNamespaceExports = function(ns) {
    result <- actual(ns)
    if (identical(ns, "tools")) setdiff(result, "sha256sum") else result
  }, .package = "base")
  expected <- "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  path <- withr::local_tempfile()
  writeBin(charToRaw("abc"), path)
  expect_identical(independent_sha256(path), expected)
  expect_identical(independent_sha256(bytes = charToRaw("abc")), expected)
})
