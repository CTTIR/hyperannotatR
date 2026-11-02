skip_if_not_installed("httpuv")
skip_if_not_installed("later")
skip_if_not_installed("png")

control_start_session <- function(root) {
  image <- file.path(root, "tiny.png")
  png::writePNG(matrix(0, 4L, 4L), image)
  at_session(image, out_dir = file.path(root, "session"))
}

# Failed-start regressions must also clean up against the unfixed package.
# Limit cleanup to the hubs the test itself started.
control_start_cleanup <- function(previous) {
  for (id in setdiff(ls(.control_registry), previous)) {
    hub <- .control_registry[[id]]
    hub$manifest_path <- NA_character_
    .control_shutdown(hub, "test cleanup")
  }
}

for (serving in c(FALSE, TRUE)) {
  test_that(paste("a non-directory control root starts nothing; serve", serving), {
    root <- withr::local_tempdir()
    session <- control_start_session(root)
    bad_root <- file.path(root, "regular-file")
    writeLines("keep this file", bad_root)
    token <- file.path(root, "new-token")
    hubs <- ls(.control_registry)
    tokens <- ls(.control_tokens)
    servers <- httpuv::listServers()
    withr::defer(control_start_cleanup(hubs))
    err <- suppressWarnings(tryCatch(
      at_control_start(session, root = bad_root, token_file = token,
                        serve = serving), error = identity
    ))
    expect_s3_class(err, "at_io_error")
    expect_identical(err$code, "INVALID_PATH")
    expect_identical(ls(.control_registry), hubs)
    expect_identical(ls(.control_tokens), tokens)
    expect_identical(httpuv::listServers(), servers)
    expect_false(file.exists(token))
    expect_identical(readLines(bad_root), "keep this file")
  })

  test_that(paste("manifest failure rolls back only this start; serve", serving), {
    later::with_temp_loop({
      root <- withr::local_tempdir()
      session <- control_start_session(root)
      control_root <- file.path(root, "control")
      dir.create(control_root)
      keep <- file.path(control_root, "existing.txt")
      writeLines("user data", keep)
      token <- file.path(root, "new-token")
      other <- httpuv::startServer("127.0.0.1", httpuv::randomPort(), list(
        call = function(req) list(status = 200L, headers = list(), body = "ok")
      ))
      withr::defer(httpuv::stopServer(other))
      cancel_other <- later::later(function() NULL, delay = 60)
      withr::defer(cancel_other())
      hubs <- ls(.control_registry)
      tokens <- ls(.control_tokens)
      servers <- httpuv::listServers()
      withr::defer(control_start_cleanup(hubs))
      # Fail the actual filesystem publication after the listener and its
      # expiry timer exist, keeping token creation and all other I/O real.
      local_mocked_bindings(.rename_path = function(from, to) {
        if (grepl("^annotatr-control-.*[.]json$", basename(to))) return(FALSE)
        file.rename(from, to)
      })
      err <- tryCatch(at_control_start(session, root = control_root,
                                        token_file = token, serve = serving),
                      error = identity)
      expect_s3_class(err, "at_io_error")
      expect_identical(err$code, "WRITE_FAILED")
      expect_identical(ls(.control_registry), hubs)
      expect_identical(ls(.control_tokens), tokens)
      expect_identical(httpuv::listServers(), servers)
      expect_false(file.exists(token))
      expect_identical(readLines(keep), "user data")
      expect_identical(list.files(control_root, all.files = TRUE, no.. = TRUE),
                       "existing.txt")
      expect_true(cancel_other())
      later::run_now(0)
      expect_true(later::loop_empty())
    })
  })
}
