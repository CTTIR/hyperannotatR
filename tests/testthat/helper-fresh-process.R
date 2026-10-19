# How a new R process loads the hyperannotatR build under test: this checkout's
# source tree for a development run, otherwise the installed copy the tests
# run from (a check or coverage library, whose installed R/ holds no .R
# sources), never an older installed package.
fresh_loader <- function() {
  src <- normalizePath(testthat::test_path("..", ".."), mustWork = FALSE)
  if (file.exists(file.path(src, "DESCRIPTION")) &&
      length(list.files(file.path(src, "R"), pattern = "[.][Rr]$")) > 0L) {
    return(sprintf("pkgload::load_all(%s, quiet = TRUE)", deparse(src)))
  }
  sprintf("library(hyperannotatR, lib.loc = %s)", deparse(dirname(find.package("hyperannotatR"))))
}

# Run `code` in a new R process and return its value. The code sees `args`
# and the package's internal helpers in either load mode.
audit_fresh <- function(code, args) {
  script <- tempfile(fileext = ".R")
  result <- tempfile(fileext = ".rds")
  log <- tempfile(fileext = ".log")
  on.exit(unlink(c(script, result, log)))
  writeLines(c(
    sprintf(".libPaths(%s)", paste(deparse(.libPaths()), collapse = "")),
    fresh_loader(),
    # `args` lives in the evaluation environment: below the namespace it
    # would otherwise resolve to base::args().
    "env <- new.env(parent = asNamespace('hyperannotatR'))",
    sprintf("env$args <- %s", paste(deparse(args), collapse = "")),
    paste0("result <- local({", code, "}, envir = env)"),
    sprintf("saveRDS(result, %s)", deparse(result))
  ), script)
  status <- system2(file.path(R.home("bin"), "Rscript"), shQuote(script), stdout = log, stderr = log)
  if (status != 0L) {
    cli::cli_abort(c("The fresh R process failed.", "i" = "{readLines(log, warn = FALSE)}"))
  }
  readRDS(result)
}
