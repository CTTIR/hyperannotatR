# Project and session serialisation as full-fidelity RDS, with a version stamp
# and a migration hook so future versions can upgrade older files.

# Compare a stored hyperannotatR version against the installed one, warn if the file
# is from a newer version, and run the (currently trivial) migration chain.
.migrate_object <- function(obj, stored_version, call = rlang::caller_env()) {
  inst <- .pkg_version()
  if (!is.null(stored_version) && !is.na(stored_version) &&
      utils::compareVersion(as.character(stored_version), inst) > 0) {
    cli::cli_warn(c(
      "This file was written by a newer hyperannotatR ({stored_version} > {inst}).",
      "i" = "Some fields may not load correctly; upgrade hyperannotatR to be safe."
    ))
  }
  # Schema migrations are applied by the persistence layer (R/persistence.R).
  obj
}

#' Save a project
#'
#' The project is written atomically: to a temporary file in the target
#' directory that then replaces `path`, so a failed write keeps the previous
#' file. An image read with [at_read_image()] is saved with a versioned source
#' descriptor (path, reader, options and file signature) instead of its
#' pixels, and is reopened from it on load. A hand-built in-memory image keeps
#' its pixels.
#'
#' @param project An [annot_project].
#' @param path Output `.rds` path.
#' @param overwrite Logical; overwrite an existing file. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#' @return The path, invisibly.
#' @family io
#' @seealso [at_load_project()], [at_inspect_saved()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE)
#' p <- tempfile(fileext = ".rds")
#' at_save_project(at_example_project(), p)
at_save_project <- function(project, path, overwrite = FALSE,
                            call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(path, call = call)
  .check_flag(overwrite, call = call)
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(c("{.path {path}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to replace it."), call = call)
  }
  project <- .prepare_project(project)
  .atomic_save_rds(project, path, overwrite = overwrite, call = call)
  invisible(path)
}

#' Load a project
#'
#' @param path Path to a saved project `.rds`.
#' @param call The calling environment, for error reporting.
#' @return The [annot_project]. Its image is reopened from the saved source
#'   descriptor; when the source is missing, changed or ambiguous the
#'   annotations still load, pixel access fails with a pointer to
#'   [at_relink_source()], and [at_inspect_source()] reports why. Warns if the
#'   file was written by a newer hyperannotatR.
#' @family io
#' @export
at_load_project <- function(path, call = rlang::caller_env()) {
  .check_file(path, call = call)
  obj <- readRDS(path)
  .check_project(obj, arg = "path", call = call)
  ver <- obj$provenance$saved_with %||% obj$provenance$annotatR_version
  .restore_project(.migrate_object(obj, ver, call = call))
}

#' Save a session
#'
#' The session is written atomically, with each stored project's image saved
#' as a source descriptor rather than pixels (see [at_save_project()]).
#'
#' @param session An [annot_session].
#' @param path Optional output path; defaults to `_session.rds` in `out_dir`.
#' @param overwrite Logical; overwrite an existing file, including the default
#'   `_session.rds`. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#' @return The session as saved (validated, with persisted projects),
#'   invisibly.
#' @family io
#' @seealso [at_load_session()], [at_resume()]
#' @export
at_save_session <- function(session, path = NULL, overwrite = FALSE,
                            call = rlang::caller_env()) {
  .check_session(session, call = call)
  .check_flag(overwrite, call = call)
  session <- .prepare_session(session)
  path <- path %||% file.path(session$out_dir, "_session.rds")
  if (!is.null(path) && file.exists(path) && !overwrite) {
    cli::cli_abort(c("{.path {path}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to replace it."), call = call)
  }
  .atomic_save_rds(session, path, overwrite = overwrite, call = call)
  invisible(session)
}

#' Load a session
#'
#' @param path Path to a saved session `.rds`.
#' @param call The calling environment, for error reporting.
#' @return The [annot_session]. A file written before sessions recorded queue
#'   entry identities gets one per queue row. Stored projects are reopened
#'   lazily by [at_current()]. Warns if written by a newer hyperannotatR.
#' @family io
#' @seealso [at_save_session()], [at_resume()]
#' @export
at_load_session <- function(path, call = rlang::caller_env()) {
  obj <- .session_load(path, call = call)
  obj <- .migrate_object(obj, obj$meta$annotatR_version, call = call)
  obj$projects <- lapply(obj$projects, function(p) {
    if (is.null(p)) NULL else .restore_project(p, materialize = FALSE)
  })
  obj
}
