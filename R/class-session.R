# The annot_session class: a resumable batch-annotation session over a queue of
# images, with a manifest, a cursor, per-image projects (materialised lazily),
# and shared label/layer templates.

# Allowed manifest status values.
.session_statuses <- c("pending", "in_progress", "complete", "flagged", "skipped")

.entry_export_stem <- function(entry_id) entry_id

# A fresh manifest. Each queue entry gets a persisted identity (`entry_id`)
# independent of its path and display name; `export_stem` names its files.
.session_manifest <- function(paths, entry_id = NULL) {
  n <- length(paths)
  if (is.null(entry_id)) {
    entry_id <- vapply(seq_len(n), function(i) .new_identity_id("entry"), character(1))
  }
  tibble::tibble(
    idx          = seq_len(n),
    entry_id     = entry_id,
    export_stem  = unname(vapply(entry_id, .entry_export_stem, character(1))),
    path         = as.character(paths),
    name         = tools::file_path_sans_ext(basename(paths)),
    status       = rep("pending", n),
    project_path = rep(NA_character_, n),
    n_rois       = rep(0L, n),
    modified     = as.POSIXct(rep(NA_real_, n), origin = "1970-01-01", tz = "UTC")
  )
}

# Entry identities must be present, safe and unique: they key checkpoint files,
# exports and project-to-entry joins.
.validate_manifest_identity <- function(manifest,
                                        call = rlang::caller_env()) {
  required <- c("entry_id", "export_stem")
  missing <- setdiff(required, names(manifest))
  if (length(missing)) {
    cli::cli_abort(
      c(
        "The session manifest has no persisted queue identity.",
        "x" = "Missing field{?s}: {.field {missing}}."
      ),
      call = call
    )
  }
  entry_id <- manifest$entry_id
  export_stem <- manifest$export_stem
  valid_entry <- is.character(entry_id) && length(entry_id) == nrow(manifest) &&
    !anyNA(entry_id) && all(nzchar(entry_id)) &&
    all(grepl("^[A-Za-z0-9._-]+$", entry_id))
  if (!valid_entry) {
    cli::cli_abort(
      "Manifest entry identifiers must be non-empty safe strings.",
      call = call
    )
  }
  if (anyDuplicated(entry_id)) {
    cli::cli_abort("Manifest entry identifiers must be unique.", call = call)
  }
  valid_stem <- is.character(export_stem) && length(export_stem) == nrow(manifest) &&
    !anyNA(export_stem) && all(nzchar(export_stem)) &&
    all(grepl("^[A-Za-z0-9._-]+$", export_stem))
  if (!valid_stem) {
    cli::cli_abort(
      "Manifest export stems must be non-empty safe file stems.",
      call = call
    )
  }
  if (anyDuplicated(export_stem)) {
    cli::cli_abort("Manifest export stems must be unique.", call = call)
  }
  invisible(manifest)
}

new_annot_session <- function(manifest,
                              projects,
                              cursor = 1L,
                              labels = character(),
                              layer_spec = list(),
                              out_dir = .session_out_dir(),
                              autosave = TRUE,
                              meta = list()) {
  .validate_manifest_identity(manifest)
  structure(
    list(
      manifest   = manifest,
      projects   = projects,
      cursor     = as.integer(cursor),
      labels     = as.character(labels),
      layer_spec = layer_spec,
      out_dir    = as.character(out_dir),
      autosave   = isTRUE(autosave),
      meta       = meta
    ),
    class = "annot_session"
  )
}

.check_session <- function(x, arg = rlang::caller_arg(x), call = rlang::caller_env()) {
  .check_class(x, "annot_session", arg = arg, call = call)
}

# Coerce a `layers` template argument to a list of annot_layer.
.normalize_layer_spec <- function(layers, call = rlang::caller_env()) {
  if (is.null(layers)) {
    return(list())
  }
  if (inherits(layers, "annot_layer")) {
    return(list(layers))
  }
  if (is.list(layers) && all(vapply(layers, inherits, logical(1), "annot_layer"))) {
    return(layers)
  }
  cli::cli_abort(
    c(
      "{.arg layers} must be `NULL`, an {.cls annot_layer}, or a list of them.",
      "x" = "You supplied {.cls {class(layers)[1]}}."
    ),
    call = call
  )
}

#' Create a batch annotation session
#'
#' @param paths Character vector of image file paths forming the queue.
#' @param labels Character vector of the global label vocabulary. Duplicates
#'   are dropped.
#' @param layers An [annot_layer], a list of them, or `NULL`. Applied as a
#'   template to every image visited.
#' @param out_dir Directory for autosave and exports. Defaults to a new,
#'   unique directory under [tempdir()], which R deletes when the process
#'   ends: pass a persistent directory to keep autosaved work. Separate
#'   sessions never share a default directory. A relative path is resolved
#'   against the working directory when the session is created.
#' @param autosave Logical; whether to autosave on annotation commits. Default
#'   `TRUE`.
#' @param ... Additional named session metadata.
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_session] with a manifest over `paths`, all statuses
#'   `"pending"`, the cursor at the first image, and projects not yet
#'   materialised.
#' @family sessions
#' @seealso [at_next()], [at_current()], [at_resume()]
#' @export
#' @examples
#' # Build a session over the bundled example image copied several times:
#' # sess <- at_example_session(3)
at_session <- function(paths, labels = character(), layers = NULL,
                       out_dir = .session_out_dir(), autosave = TRUE, ...,
                       call = rlang::caller_env()) {
  if (!is.character(paths) || length(paths) == 0L) {
    cli::cli_abort(
      c(
        "{.arg paths} must be a non-empty character vector of image paths.",
        "x" = "You supplied {.cls {class(paths)[1]}} of length {length(paths)}."
      ),
      call = call
    )
  }
  missing <- is.na(paths) | !file.exists(paths)
  if (any(missing)) {
    cli::cli_abort(
      c(
        "Every path in {.arg paths} must exist.",
        "x" = "Missing: {.path {paths[missing]}}."
      ),
      call = call
    )
  }
  is_dir <- dir.exists(paths)
  if (any(is_dir)) {
    .check_abort(
      c(
        "Every path in {.arg paths} must be an image file, not a directory.",
        "x" = "Director{?y/ies}: {.path {paths[is_dir]}}.",
        "i" = "List the images first, e.g. {.code list.files(dir, full.names = TRUE)}."
      ),
      call = call
    )
  }
  .check_string(out_dir, call = call)
  # Store absolute paths: the session reads images lazily, and launchers such as
  # at_annotate() change the working directory (shiny::runApp), so a relative
  # path would no longer resolve at read time. The autosave/export directory is
  # resolved the same way so those writes land where the caller intended.
  paths <- normalizePath(paths, mustWork = FALSE)
  if (!grepl("^(?:/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path.expand(out_dir), perl = TRUE)) {
    out_dir <- file.path(getwd(), out_dir)
  }
  out_dir <- normalizePath(path.expand(out_dir), mustWork = FALSE)
  .check_flag(autosave, call = call)
  n <- length(paths)
  manifest <- .session_manifest(paths)
  new_annot_session(
    manifest   = manifest,
    projects   = vector("list", n),
    cursor     = 1L,
    labels     = unique(as.character(labels)),
    layer_spec = .normalize_layer_spec(layers, call = call),
    out_dir    = out_dir,
    autosave   = autosave,
    meta       = list(...)
  )
}

# ---- Navigation ------------------------------------------------------------

#' Advance to the next image
#' @param session An [annot_session].
#' @param call The calling environment, for error reporting.
#' @return A new [annot_session] with the cursor advanced (clamped at the end).
#' @family sessions
#' @export
at_next <- function(session, call = rlang::caller_env()) {
  .check_session(session, call = call)
  session$cursor <- min(session$cursor + 1L, nrow(session$manifest))
  session
}

#' Step back to the previous image
#' @inheritParams at_next
#' @return A new [annot_session] with the cursor decremented (clamped at 1).
#' @family sessions
#' @export
at_prev <- function(session, call = rlang::caller_env()) {
  .check_session(session, call = call)
  session$cursor <- max(session$cursor - 1L, 1L)
  session
}

#' Jump to a specific image
#' @inheritParams at_next
#' @param i Integer image index (1-based) within the queue.
#' @return A new [annot_session] with the cursor at `i`.
#' @family sessions
#' @export
at_goto <- function(session, i, call = rlang::caller_env()) {
  .check_session(session, call = call)
  i <- .check_count(i, min = 1L, call = call)
  n <- nrow(session$manifest)
  if (i > n) {
    cli::cli_abort(
      c("{.arg i} is out of range.", "x" = "The queue has {n} image{?s}; got {i}."),
      call = call
    )
  }
  session$cursor <- i
  session
}

#' The current project
#'
#' Return the project for the image at the cursor, materialising it from the
#' image (and applying the session's layer template) if it has not been visited.
#' A stored project whose pixel handle was not saved is reopened from its
#' recorded source (see [at_inspect_source()] when that is impossible).
#'
#' @inheritParams at_next
#' @return An [annot_project].
#' @family sessions
#' @export
at_current <- function(session, call = rlang::caller_env()) {
  .check_session(session, call = call)
  .materialize_project(session, session$cursor)
}

# ---- Status and manifest ---------------------------------------------------

#' Set the status of a queued image
#' @inheritParams at_goto
#' @param status One of `"pending"`, `"in_progress"`, `"complete"`,
#'   `"flagged"`, `"skipped"`.
#' @return A new [annot_session] with the status updated.
#' @family sessions
#' @export
at_set_status <- function(session, i, status, call = rlang::caller_env()) {
  .check_session(session, call = call)
  i <- .check_count(i, min = 1L, call = call)
  status <- .check_choice(status, .session_statuses, default = missing(status), call = call)
  n <- nrow(session$manifest)
  if (i > n) {
    cli::cli_abort(
      c("{.arg i} is out of range.", "x" = "The queue has {n} image{?s}; got {i}."),
      call = call
    )
  }
  session$manifest$status[i] <- status
  session
}

#' The session manifest
#' @inheritParams at_next
#' @return The manifest [tibble::tibble] with columns `idx`, `entry_id`,
#'   `export_stem`, `path`, `name`, `status`, `project_path`, `n_rois`, and
#'   `modified`.
#' @family sessions
#' @export
at_session_status <- function(session, call = rlang::caller_env()) {
  .check_session(session, call = call)
  session$manifest
}

#' Session progress manifest with per-label counts
#'
#' @inheritParams at_next
#' @return A [tibble::tibble] with `idx`, `entry_id`, `export_stem`, `name`,
#'   `path`, `status`, `n_layers`, `n_rois`, and one integer column per label in
#'   the session vocabulary giving its ROI count per image. `n_rois` counts the
#'   ROIs of materialised projects (otherwise the manifest's stored count). A
#'   label that clashes with one of the fixed column names gets a `label_`
#'   prefix.
#' @family sessions
#' @export
at_manifest <- function(session, call = rlang::caller_env()) {
  .check_session(session, call = call)
  m <- session$manifest
  labels <- unique(as.character(session$labels))
  n <- nrow(m)
  tables <- lapply(seq_len(n), function(i) {
    proj <- session$projects[[i]]
    if (is.null(proj)) NULL else at_rois(proj)
  })
  counts <- lapply(tables, function(rt) {
    out <- if (is.null(rt)) rep(0L, length(labels)) else
      vapply(labels, function(lb) sum(rt$label == lb), integer(1))
    names(out) <- labels
    out
  })
  n_layers <- vapply(seq_len(n), function(i) {
    proj <- session$projects[[i]]
    if (is.null(proj)) 0L else length(proj$layers)
  }, integer(1))
  n_rois <- vapply(seq_len(n), function(i) {
    if (is.null(tables[[i]])) as.integer(m$n_rois[i]) else nrow(tables[[i]])
  }, integer(1))
  base <- tibble::tibble(
    idx         = m$idx,
    entry_id    = m$entry_id,
    export_stem = m$export_stem,
    name        = m$name,
    path        = m$path,
    status      = m$status,
    n_layers    = n_layers,
    n_rois      = n_rois
  )
  if (length(labels) > 0L) {
    count_mat <- matrix(unlist(counts, use.names = FALSE), nrow = n, byrow = TRUE)
    cols <- ifelse(labels %in% names(base), paste0("label_", labels), labels)
    count_tbl <- tibble::as_tibble(
      stats::setNames(as.data.frame(count_mat), cols),
      .name_repair = "minimal"
    )
    base <- dplyr::bind_cols(base, count_tbl)
  }
  base
}

# ---- Persistence -----------------------------------------------------------

# Compatibility wrappers delegate to the versioned persistence contract.
.session_save <- function(session, path = NULL, call = rlang::caller_env()) {
  at_save_session(session, path = path, overwrite = TRUE, call = call)
}

.session_load <- function(path, call = rlang::caller_env()) {
  .check_file(path, call = call)
  obj <- readRDS(path)
  .check_session(obj, arg = "path", call = call)
  obj <- .migrate_session(obj)
  obj
}

#' Resume a saved session
#'
#' A more discoverable alias for [at_load_session()].
#'
#' @param path Path to a saved session `.rds` file.
#' @param call The calling environment, for error reporting.
#' @return The restored [annot_session].
#' @family sessions
#' @seealso [at_save_session()], [at_load_session()]
#' @export
at_resume <- function(path, call = rlang::caller_env()) {
  at_load_session(path, call = call)
}

# ---- S3 methods ------------------------------------------------------------

#' @export
format.annot_session <- function(x, ...) {
  m <- x$manifest
  done <- sum(m$status == "complete")
  c(
    cli::format_inline("{.cls annot_session}"),
    cli::format_inline("images: {nrow(m)}  |  complete: {done}  |  cursor: {x$cursor}"),
    cli::format_inline("out_dir: {.path {x$out_dir}}  |  autosave: {x$autosave}")
  )
}

#' @export
print.annot_session <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}
