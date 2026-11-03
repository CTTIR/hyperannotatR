# Remove genuine links before withr's recursive temporary-directory cleanup.
# R's Windows unlink can reject a reparse point that it successfully created.
portable_test_link <- function(from, to, envir = parent.frame()) {
  from <- normalizePath(from, winslash = "/", mustWork = file.exists(from))
  # fs uses directory junctions on Windows, including for file targets.
  # Base R creates genuine file symlinks; keep fs for directory junctions.
  if (.Platform$OS.type == "windows" && !dir.exists(from)) {
    if (!isTRUE(file.symlink(from, to))) stop("Cannot create the required file symlink fixture.")
  } else {
    fs::link_create(from, to)
  }
  withr::defer(fs::link_delete(to[fs::is_link(to)]), envir = envir)
  invisible(TRUE)
}

# Independent implementation on R versions without tools::sha256sum().
# The package uses digest there; OpenSSL remains an independent oracle.
independent_sha256 <- function(path = NULL, bytes = NULL) {
  if ("sha256sum" %in% getNamespaceExports("tools")) {
    if (!is.null(path)) return(unname(tools::sha256sum(path)))
    return(unname(tools::sha256sum(bytes = bytes)))
  }
  testthat::skip_if_not_installed("openssl")
  if (!is.null(path)) {
    con <- file(path, "rb")
    on.exit(close(con))
    return(unname(unclass(as.character(openssl::sha256(con)))))
  }
  unname(unclass(as.character(openssl::sha256(bytes))))
}
