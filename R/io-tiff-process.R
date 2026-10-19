# Decode in a fresh process because native TIFF callback state is shared by
# independently loaded codecs. No display library is loaded in the child.
.tiff_read_isolated <- function(path, ...) {
  timeout <- getOption("hyperannotatR.tiff_timeout", 120)
  if (!is.numeric(timeout) || length(timeout) != 1L || !is.finite(timeout) ||
        timeout < 1 || timeout != floor(timeout) ||
        timeout > .Machine$integer.max) {
    stop( # nolint: cttir_condition. Preserve base decoder conditions.
      "hyperannotatR.tiff_timeout must be a finite integer of at least one second",
      call. = FALSE
    )
  }
  work <- tempfile("annotatr-tiff-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  request <- file.path(work, "request.rds")
  response <- file.path(work, "response.rds")
  script <- file.path(work, "decode.R")
  log <- file.path(work, "decode.log")
  saveRDS(list(
    path = normalizePath(path, mustWork = TRUE), args = list(...),
    libraries = .libPaths()
  ), request)
  writeLines(c(
    "args <- commandArgs(TRUE)",
    "request <- readRDS(args[[1]])",
    ".libPaths(request$libraries)",
    "warnings <- character()",
    "result <- tryCatch({",
    "  value <- withCallingHandlers(",
    "    do.call(tiff::readTIFF, c(list(source=request$path), request$args)),",
    "    warning=function(w) {",
    "      warnings <<- c(warnings, conditionMessage(w))",
    "      invokeRestart('muffleWarning')})",
    "  list(ok=TRUE, value=value, warnings=warnings)",
    "}, error=function(e) list(ok=FALSE, error=conditionMessage(e)))",
    "# Uncompressed: gzip of a large decoded image costs more than the decode.",
    "saveRDS(result, args[[2]], compress=FALSE)"
  ), script)
  arguments <- c(
    "--vanilla", "--default-packages=NULL", script, request, response
  )
  status <- system2(file.path(R.home("bin"), "Rscript"),
    shQuote(arguments),
    stdout = log, stderr = log, timeout = timeout
  )
  if (status != 0L || !file.exists(response)) {
    why <- if (identical(as.integer(status), 124L)) {
      sprintf("timed out after %d s (option hyperannotatR.tiff_timeout)", as.integer(timeout))
    } else {
      sprintf("exit %s", status)
    }
    tail_log <- if (file.exists(log)) utils::tail(readLines(log, warn = FALSE), 5L) else character()
    tail_log <- tail_log[nzchar(trimws(tail_log))]
    stop( # nolint: cttir_condition. Preserve base decoder conditions.
      paste0(
        sprintf("Isolated TIFF decoder failed (%s); no image returned", why),
        if (length(tail_log)) paste0("\n", paste(tail_log, collapse = "\n")) else ""
      ),
      call. = FALSE
    )
  }
  result <- readRDS(response)
  if (!isTRUE(result$ok)) {
    # Forward the decoder text without CLI interpolation or formatting.
    stop(result$error, call. = FALSE) # nolint: cttir_condition.
  }
  for (message in result$warnings) {
    warning(message, call. = FALSE) # nolint: cttir_condition.
  }
  result$value
}
