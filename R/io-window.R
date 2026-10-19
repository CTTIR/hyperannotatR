# Windowed reads: read telemetry, window budgets, the native OME window and the
# public capability/close lifecycle.

# ---- Read telemetry ----------------------------------------------------------

# Counters are logical bytes delivered by the binary readers, never OS traffic.
# Native APIs (RBioFormats) expose decoded requests only; their encoded I/O is
# unknown and recorded as NA.
.read_io <- new.env(parent = emptyenv())

.read_telemetry_reset <- function() {
  .read_io$counts <- list(binary_bytes = 0, binary_calls = 0, native_metadata_calls = 0,
                          native_window_calls = 0, native_file_bytes = 0, decoded_bytes = 0)
  invisible(NULL)
}

.read_telemetry <- function() {
  if (is.null(.read_io$counts)) .read_telemetry_reset()
  .read_io$counts
}

.read_telemetry_add <- function(...) {
  counts <- .read_telemetry()
  add <- list(...)
  for (k in names(add)) counts[[k]] <- counts[[k]] + add[[k]]
  .read_io$counts <- counts
  invisible(NULL)
}

# Read exactly `n` raw bytes from `con`, counting them.
.window_read_raw <- function(con, n, call = rlang::caller_env()) {
  x <- readBin(con, "raw", n = n)
  .read_telemetry_add(binary_bytes = length(x), binary_calls = 1)
  if (length(x) != n) {
    .at_abort("Short/truncated window or header.", class = "io", code = "PAYLOAD_SHORT",
              call = call)
  }
  x
}

# ---- Capabilities -------------------------------------------------------------

.window_capabilities <- function(io) {
  list(metadata_only = TRUE, window_read = TRUE, samples = "raw-scalar-v1", io = io,
       lifecycle = "per-read connections")
}

.eager_capabilities <- function(samples = "raw-scalar-v1") {
  list(metadata_only = FALSE, window_read = FALSE, samples = samples, io = "eager")
}

# Does the handle hold decoded pixels in memory?
.memory_snapshot <- function(img) {
  h <- img[["handle"]]
  is.list(h) && (is.array(h[["data"]]) ||
    (is.list(h[["levels"]]) && length(h[["levels"]]) > 0L &&
       all(vapply(h[["levels"]], is.array, logical(1)))))
}

# Number of samples in an nx x ny x nb window, checked against R indexing and
# the read budget before allocation.
.window_budget <- function(nx, ny, nb, call = rlang::caller_env()) {
  n <- as.double(nx) * ny * nb
  if (!is.finite(n) || n > .Machine$integer.max) {
    .at_abort("Window exceeds supported array indexing limits.", class = "limit",
              code = "TILE_TOO_LARGE", call = call)
  }
  .read_budget(n * 8, call = call)
  n
}

# ---- Native OME windows --------------------------------------------------------

# Read one window of an OME level through RBioFormats subsetting. Bio-Formats
# returns [x, y, c]; the result is the [y, x, band] tile contract.
.ome_window <- function(img, level, xrange, yrange, bands) {
  h <- img[["handle"]]
  core <- h[["layout"]][[level + 1L]]
  n <- .window_budget(diff(xrange) + 1, diff(yrange) + 1,
                      if (is.null(bands)) img$n_bands else length(bands))
  xs <- seq.int(xrange[1], xrange[2])
  ys <- seq.int(yrange[1], yrange[2])
  bs <- bands %||% seq_len(img$n_bands)
  ub <- sort(unique(bs))
  .read_telemetry_add(native_window_calls = 1, native_file_bytes = NA_real_)
  a <- as.array(RBioFormats::read.image(h[["path"]], series = h[["series"]],
                                        resolution = core$resolutionLevel,
                                        subset = list(x = xs, y = ys, c = ub),
                                        normalize = FALSE, read.metadata = FALSE))
  .read_telemetry_add(decoded_bytes = n * 8)
  want <- c(length(xs), length(ys), length(ub))
  if (length(a) != prod(want) || !identical(as.integer(dim(a)[1:2]), as.integer(want[1:2]))) {
    .at_abort("OME window axes disagree with the request.", class = "io",
              code = "BACKEND_CONTRACT")
  }
  a <- aperm(array(a, dim = want), c(2, 1, 3))
  storage.mode(a) <- "double"
  a[, , match(bs, ub), drop = FALSE]
}

# ---- Public lifecycle ------------------------------------------------------------

#' Inspect the effective reading capabilities of an image
#'
#' Report how an image's pixels are read: whether opening it reads metadata
#' only, whether tiles are read as windows from the file, what the samples
#' mean, and where they come from.
#'
#' @param x An [annot_image] or [annot_project].
#' @return A list with `metadata_only` and `window_read` (logical; `NA` when a
#'   third-party backend does not declare them), `samples` (`"raw-scalar-v1"`
#'   for stored values, `"display-converted-0-255"` for display conversions,
#'   `"unqualified"` when undeclared) and `io` (`"binary"`, `"native"`,
#'   `"eager"`, `"memory"` or `"unknown"`), plus an optional `lifecycle`. An
#'   image whose handle holds decoded pixels reports memory access even for a
#'   backend that normally reads windows.
#' @family images
#' @family backends
#' @export
#' @examples
#' at_image_capabilities(at_example_image("cube"))$window_read
at_image_capabilities <- function(x) {
  img <- if (inherits(x, "annot_project")) x[["image"]] else x
  .check_image(img)
  cap <- img[["meta"]][["capabilities"]]
  if (is.null(cap)) {
    cap <- at_backend_get(img[["backend"]])[["capabilities"]] %||%
      list(metadata_only = NA, window_read = NA, samples = "unqualified", io = "unknown")
  }
  if (.memory_snapshot(img)) {
    cap$metadata_only <- FALSE
    cap$window_read <- FALSE
    cap$io <- "memory"
    cap$lifecycle <- "retained pixel snapshot"
  }
  cap
}

#' Release an image handle
#'
#' Drop an image's runtime pixel handle, calling the backend's `close_fn` when
#' it declares one.
#'
#' @param x An [annot_image] or [annot_project].
#' @return The image or project with its runtime handle released; assign the
#'   result. Later tile requests reopen the image from its source. Releasing a
#'   retained pixel snapshot loses those pixels when the source has changed or
#'   cannot be reopened. Built-in window readers open a connection per read and
#'   hold no persistent connection.
#' @family images
#' @family backends
#' @export
#' @examples
#' cube <- at_close_image(at_example_image("cube"))
#' dim(at_tile(cube, xrange = c(1, 4), yrange = c(1, 4), bands = 1))
at_close_image <- function(x) {
  project <- inherits(x, "annot_project")
  img <- if (project) x[["image"]] else x
  .check_image(img)
  close_fn <- at_backend_get(img[["backend"]])[["close_fn"]]
  if (!is.null(img[["handle"]]) && is.function(close_fn)) close_fn(img)
  img$handle <- NULL
  # Cached tiles of the closed read must never be served again; a fresh read
  # identity is minted when the handle is reopened.
  img$cache_identity <- .new_identity_id("closed")
  img$read_generation <- NULL
  if (project) {
    x$image <- img
    x
  } else {
    img
  }
}
