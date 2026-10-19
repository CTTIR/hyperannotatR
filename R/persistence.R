# Versioned persistence: source descriptors that let a saved project reopen its
# image, atomic checkpoint writes, legacy migration, and explicit source
# inspection and relinking. Pixel handles are runtime state; descriptors are the
# durable record of how to rebuild them.

# Persistence schemas are independent of the package release version.
.persistence_schema <- 1L
.source_schema <- 1L
.session_out_dir <- function() tempfile("hyperannotatR-session-")

.source_signature <- function(path) {
  if (!file.exists(path)) return(NULL)
  info <- file.info(path)
  list(size = unname(info$size), mtime = unname(as.numeric(info$mtime)))
}

# Ordered, semantic file roles make companion inputs durable and comparable,
# e.g. c(header = <.hdr>, payload = <.dat>) for an ENVI cube. (Named apart from
# the interop manifest's .source_files(), which describes files for partners.)
.persisted_source_files <- function(paths) {
  lapply(paths, function(p) {
    list(path = normalizePath(p, mustWork = TRUE), signature = .source_signature(p))
  })
}

.validate_source_files <- function(files) {
  if (is.null(files)) return(invisible(NULL))
  if (!is.list(files) || !length(files) || is.null(names(files)) || anyNA(names(files)) ||
      any(!nzchar(names(files))) || anyDuplicated(names(files))) {
    .at_fail("Invalid composite source files.", class = "validation", code = "INVALID_SOURCE")
  }
  for (f in files) {
    if (!is.list(f)) .at_fail("Invalid composite source file.", class = "validation", code = "INVALID_SOURCE")
    .check_provenance_keys(f, c("path", "signature"), "source file")
    .check_string(f[["path"]])
    sig <- f[["signature"]]
    .check_provenance_keys(sig, c("size", "mtime"), "source file signature")
    if (!.valid_signature(sig)) .at_fail("Invalid composite source signature.", class = "validation", code = "INVALID_SOURCE")
  }
  invisible(files)
}

.valid_signature <- function(sig) {
  is.list(sig) && is.numeric(sig[["size"]]) && length(sig[["size"]]) == 1L &&
    is.finite(sig[["size"]]) && sig[["size"]] >= 0 && is.numeric(sig[["mtime"]]) &&
    length(sig[["mtime"]]) == 1L && is.finite(sig[["mtime"]])
}

# A composite source whose companion inputs were not recorded cannot be
# verified against the saved image (a replaced header or payload would pass).
.composite_unverified <- function(d) {
  backend <- d[["backend"]]
  files <- d[["files"]]
  if (identical(backend, "envi")) {
    return(is.null(files) || !all(c("header", "payload") %in% names(files)))
  }
  if (identical(backend, "tivita")) return(is.null(files) || !"payload" %in% names(files))
  FALSE
}

.check_schema <- function(version, what) {
  if (!is.null(version) && (!is.numeric(version) || length(version) != 1L ||
      is.na(version) || version != 1)) {
    .at_fail("Unsupported ", what, " schema. Inspect the original file and upgrade hyperannotatR.",
             class = "validation", code = "SCHEMA_UNSUPPORTED")
  }
}

# Reader options are replayed to reopen a source, so they must be plain data.
.serializable_options <- function(x) {
  if (is.environment(x) || is.function(x) || typeof(x) %in% c("externalptr", "weakref") ||
      inherits(x, "connection")) return(FALSE)
  if (is.list(x)) return(all(vapply(x, .serializable_options, logical(1))))
  is.atomic(x) || is.null(x)
}

# Extension data never aliases a supported key. Duplicate supported keys are
# ambiguous even when exact list lookup would select the first occurrence.
.check_provenance_keys <- function(x, keys, what) {
  nms <- names(x)
  if (anyDuplicated(nms[nms %in% keys])) .at_fail("Duplicate ", what, " metadata keys.", class = "validation", code = "DUPLICATE_KEY")
  invisible(x)
}

.check_descriptor_keys <- function(d) {
  if (!is.list(d)) return(invisible(d))
  .check_provenance_keys(d, c("schema_version", "path", "backend", "options",
    "options_inferred", "reader_contract", "signature", "files", "options_encoding",
    "options_identity"), "source descriptor")
  .check_provenance_keys(d[["reader_contract"]], c("axes", "samples"), "source reader contract")
  .check_provenance_keys(d[["signature"]], c("size", "mtime"), "source signature")
  invisible(d)
}

.validate_descriptor <- function(d) {
  if (!is.list(d)) .at_fail("Invalid source descriptor.", class = "validation", code = "INVALID_SOURCE")
  .check_descriptor_keys(d)
  .check_schema(d[["schema_version"]], "source")
  .check_string(d[["path"]])
  .check_string(d[["backend"]])
  if (!is.list(d[["options"]]) || !.serializable_options(d[["options"]])) {
    .at_fail("Invalid serializable reader options.", class = "validation", code = "INVALID_SOURCE")
  }
  if ("options_inferred" %in% names(d)) .check_flag(d[["options_inferred"]], arg = "options_inferred")
  if (!is.null(d[["reader_contract"]])) {
    contract <- d[["reader_contract"]]
    ok <- is.list(contract) && setequal(names(contract), c("axes", "samples")) &&
      length(contract) == 2L &&
      all(vapply(contract, function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x),
                 logical(1)))
    if (!ok) .at_fail("Invalid source reader contract.", class = "validation", code = "INVALID_SOURCE")
  }
  .validate_source_files(d[["files"]])
  sig <- d[["signature"]]
  if (!is.null(sig) && !.valid_signature(sig)) .at_fail("Invalid source signature.", class = "validation", code = "INVALID_SOURCE")
  invisible(d)
}

# Does the handle hold decoded pixel arrays (an immutable in-memory snapshot)
# rather than a reference to the file? Snapshots never need reopening.
.holds_pixel_arrays <- function(img) {
  h <- img[["handle"]]
  is.list(h) && (is.array(h[["data"]]) ||
    (is.list(h[["levels"]]) && length(h[["levels"]]) > 0L &&
       all(vapply(h[["levels"]], is.array, logical(1)))))
}

.migrate_image <- function(img) {
  .check_image(img)
  .check_provenance_keys(img, c("source_descriptor", "source", "backend", "meta", "handle"),
                         "image source")
  .check_provenance_keys(img[["meta"]], "reader_contract", "image reader contract")
  if (length(img[["dims"]]) != 2L || anyNA(img[["dims"]]) || any(img[["dims"]] < 1L) ||
      length(img[["n_bands"]]) != 1L || is.na(img[["n_bands"]]) || img[["n_bands"]] < 1L) {
    .at_fail("Invalid saved image dimensions.", class = "validation", code = "INVALID_CHECKPOINT")
  }
  d <- img[["source_descriptor"]]
  if (!is.null(d)) {
    .validate_descriptor(d)
    d[["schema_version"]] <- .source_schema
    img[["source_descriptor"]] <- d
  } else if (is.null(img[["handle"]]) && .is_string(img[["source"]]) &&
             .is_string(img[["backend"]]) &&
             img[["backend"]] %in% c("raster", "tiff", "envi", "ometiff") &&
             grepl("^(?:/|[A-Za-z]:[/\\\\]|\\\\\\\\)", img[["source"]], perl = TRUE)) {
    # Only established default readers can recover a lightweight legacy image.
    # Its original file metadata/options were not recorded; expose that fact.
    img[["source_descriptor"]] <- list(schema_version = .source_schema, path = img[["source"]],
      backend = img[["backend"]], options = list(), options_inferred = TRUE, signature = NULL)
  }
  img
}

.source_status <- function(img) {
  d <- img[["source_descriptor"]]
  if (is.null(d)) {
    return(if (!is.null(img[["handle"]])) "in_memory" else "unresolved")
  }
  .validate_descriptor(d)
  if (!file.exists(d[["path"]])) return("missing")
  if (!is.null(d[["signature"]]) && !identical(d[["signature"]], .source_signature(d[["path"]]))) {
    return("changed")
  }
  for (f in d[["files"]]) {
    if (!file.exists(f[["path"]])) return("missing")
    if (!identical(f[["signature"]], .source_signature(f[["path"]]))) return("changed")
  }
  "available"
}

#' Inspect an image source without changing annotations or reading pixels
#'
#' Report whether the file an image (or project) was read from is still
#' available and unchanged, so a saved project can be reopened or relinked
#' deliberately.
#'
#' @param x An [annot_image] or [annot_project].
#' @return A list with `status`, `path`, `backend`, `options` (the recorded
#'   reader options) and `options_inferred` (`TRUE` for a legacy image whose
#'   options were not recorded). `status` is `"available"`, `"missing"`,
#'   `"changed"`, `"in_memory"` (pixels held in memory, no source file) or
#'   `"unresolved"`. Size and modification time detect many source
#'   replacements, but are not a content checksum. Composite sources also
#'   validate every declared companion input, such as an ENVI header and
#'   payload.
#' @family io
#' @seealso [at_relink_source()], [at_inspect_saved()]
#' @export
at_inspect_source <- function(x) {
  img <- if (inherits(x, "annot_project")) x$image else x
  img <- .migrate_image(img)
  d <- img[["source_descriptor"]]
  list(status = .source_status(img), path = d[["path"]] %||% img[["source"]],
       backend = d[["backend"]] %||% img[["backend"]], options = d[["options"]],
       options_inferred = isTRUE(d[["options_inferred"]]))
}

# Rebuild a stripped pixel handle from the image's source descriptor. Retained
# arrays are immutable snapshots and are returned unchanged. A missing, changed
# or ambiguous source leaves the image without pixels (and, with
# `require_pixels`, raises an at_io_error) instead of guessing.
.reopen_image <- function(img, require_pixels = FALSE, call = rlang::caller_env()) {
  img <- .migrate_image(img)
  if (.holds_pixel_arrays(img)) return(img)
  status <- .source_status(img)
  if (status == "available" && .composite_unverified(img[["source_descriptor"]])) {
    status <- "unresolved"
    img[["meta"]][["source_error"]] <-
      "Composite source provenance is unverified; use at_relink_source() to revalidate."
  }
  if (status == "available" && is.null(img[["handle"]])) {
    d <- img[["source_descriptor"]]
    result <- tryCatch(
      do.call(at_read_image, c(list(path = d[["path"]], backend = d[["backend"]]), d[["options"]])),
      error = identity
    )
    if (!inherits(result, "error") &&
        (!identical(result[["dims"]], img[["dims"]]) ||
           !identical(result[["n_bands"]], img[["n_bands"]]) ||
           !identical(result[["level_dims"]], img[["level_dims"]]))) {
      result <- simpleError("Reopened source dimensions differ from saved image.")
    }
    if (!inherits(result, "error")) {
      fields <- c("backend", "dtype", "band_names", "wavelengths", "wavelength_unit",
                  "pixel_size", "pixel_unit")
      changed <- fields[!vapply(fields, function(k) identical(result[[k]], img[[k]]), logical(1))]
      if (length(changed) ||
          !identical(result[["meta"]][["reader_contract"]], img[["meta"]][["reader_contract"]]) ||
          !identical(result[["source_descriptor"]][["reader_contract"]], d[["reader_contract"]])) {
        result <- simpleError(paste(
          "Reopened reader metadata/decoding contract differs or is legacy-ambiguous;",
          "explicitly revalidate with at_relink_source(). Annotations are preserved."
        ))
      }
    }
    if (inherits(result, "error")) {
      img[["meta"]][["source_error"]] <- conditionMessage(result)
      status <- "unresolved"
    } else {
      if (is.null(d[["signature"]])) d[["signature"]] <- result[["source_descriptor"]][["signature"]]
      img[["source_descriptor"]] <- d
      img[["handle"]] <- result[["handle"]]
      img[["read_generation"]] <- result[["read_generation"]]
      img[["cache_identity"]] <- result[["cache_identity"]]
      img[["meta"]][["source_error"]] <- NULL
    }
  }
  if (!status %in% c("available", "in_memory")) {
    img[["handle"]] <- NULL
    if (require_pixels) {
      msg <- paste0(
        "Image source is ", status, ": ", img[["source"]], ". ",
        "Use at_inspect_source() and at_relink_source() with the original source and reader options. ",
        img[["meta"]][["source_error"]] %||% ""
      )
      .at_abort("{msg}", class = "io",
                code = if (status == "changed") "IMAGE_CHANGED" else "IMAGE_UNAVAILABLE",
                details = list(status = status), call = call)
    }
  }
  img
}

#' Explicitly relink or revalidate an image source
#'
#' Point a saved image (or project) at its source file again, for example after
#' the file moved, or accept a source that changed since it was saved. The
#' replacement is read with the selected reader and must have the same
#' geometry; annotations are never changed.
#'
#' @param x An [annot_image] or [annot_project]. Annotations and geometry are
#'   preserved.
#' @param path Replacement source path (may be the same path to revalidate).
#' @param backend Reader backend; defaults to the saved backend.
#' @param options Reader options as a list; defaults to the saved options.
#' @return The updated image or project. Dimensions, pyramid levels, band count
#'   and wavelengths must agree. Relinking explicitly accepts the new source
#'   and refreshes image metadata from the selected reader.
#' @family io
#' @seealso [at_inspect_source()]
#' @export
at_relink_source <- function(x, path, backend = NULL, options = NULL) {
  project <- inherits(x, "annot_project")
  img <- if (project) x$image else x
  .check_image(img)
  .check_provenance_keys(img, c("source_descriptor", "source", "backend", "meta", "handle"),
                         "image source")
  d <- img[["source_descriptor"]]
  .check_descriptor_keys(d)
  fresh <- do.call(at_read_image, c(
    list(path = path, backend = backend %||% d[["backend"]] %||% img[["backend"]]),
    options %||% d[["options"]] %||% list()
  ))
  if (!identical(fresh[["dims"]], img[["dims"]]) || !identical(fresh[["n_bands"]], img[["n_bands"]]) ||
      !identical(fresh[["level_dims"]], img[["level_dims"]]) ||
      !identical(fresh[["wavelengths"]], img[["wavelengths"]])) {
    .at_abort(
      "Replacement image dimensions, pyramid levels, bands or wavelengths differ; annotations were not changed.",
      class = "io", code = "IMAGE_CHANGED"
    )
  }
  # The reader owns the handle layout and all image metadata. Adopt them
  # together so tile dispatch, bands, units and backend metadata stay coherent.
  if (project) {
    x$image <- fresh
    x
  } else {
    fresh
  }
}

.validate_project_structure <- function(p) {
  .check_project(p)
  # This validates image/source schemas without opening the external source.
  .migrate_image(p$image)
  .check_schema(p$provenance$schema_version, "project")
  if (!is.list(p$layers) || (length(p$layers) &&
      (is.null(names(p$layers)) || anyDuplicated(names(p$layers))))) {
    .at_fail("Invalid saved layers.", class = "validation", code = "INVALID_CHECKPOINT")
  }
  for (layer in p$layers) {
    .check_layer(layer)
    if (!is.list(layer$rois)) .at_fail("Invalid saved ROIs.", class = "validation", code = "INVALID_CHECKPOINT")
    for (roi in layer$rois) {
      .check_roi(roi)
      .check_string(roi$id)
      if (!inherits(roi$geometry, "sfc")) .at_fail("Invalid saved ROI geometry.", class = "validation", code = "INVALID_CHECKPOINT")
    }
  }
  if (anyDuplicated(.all_roi_ids(p))) {
    .at_fail("Ambiguous duplicate ROI identifiers; inspect the original file before repair.",
             class = "validation", code = "DUPLICATE_ID")
  }
  invisible(p)
}

# Should a persisted image drop its handle? Images with a source descriptor are
# reopened from it, except legacy in-memory snapshots that carry no reader
# capabilities (or an unverifiable composite source): those pixels cannot be
# rebuilt, so they are kept.
.strip_persisted_handle <- function(img) {
  !is.null(img[["source_descriptor"]]) &&
    !(.holds_pixel_arrays(img) && is.list(img[["meta"]]) &&
        (is.null(img[["meta"]][["capabilities"]]) ||
           .composite_unverified(img[["source_descriptor"]])))
}

.prepare_project <- function(p) {
  .validate_project_structure(p)
  p$image <- .migrate_image(p$image)
  if (.strip_persisted_handle(p$image)) p$image$handle <- NULL
  p$provenance$schema_version <- .persistence_schema
  p$provenance$saved_with <- .pkg_version()
  p
}

.restore_project <- function(p, materialize = TRUE) {
  .validate_project_structure(p)
  # Persisted opaque runtime identities are never reused by a new load.
  p$image$cache_identity <- .new_identity_id("image")
  p$image$read_generation <- NULL
  if (.strip_persisted_handle(p$image)) p$image$handle <- NULL
  p$image <- if (materialize) .reopen_image(p$image) else .migrate_image(p$image)
  p$provenance$schema_version <- .persistence_schema
  # A fresh process restarts the ROI id counter; never mint a loaded id again.
  .bump_id_counter(.all_roi_ids(p))
  p
}

.migrate_session <- function(s) {
  .check_session(s)
  .check_schema(s$meta$schema_version, "session")
  m <- s$manifest
  required <- c("idx", "path", "name", "status", "project_path", "n_rois", "modified")
  if (!is.data.frame(m) || !all(required %in% names(m)) || !nrow(m) ||
      !is.numeric(m$idx) || !identical(as.numeric(m$idx), as.numeric(seq_len(nrow(m)))) ||
      !is.character(m$path) || anyNA(m$path) || any(!nzchar(m$path)) ||
      !is.character(m$project_path) || !is.character(m$name) ||
      !is.numeric(m$n_rois) || anyNA(m$n_rois) || any(m$n_rois < 0) ||
      any(m$n_rois != floor(m$n_rois)) ||
      !is.list(s$projects) || length(s$projects) != nrow(m) ||
      length(s$cursor) != 1L || !is.numeric(s$cursor) || is.na(s$cursor) ||
      s$cursor != floor(s$cursor) || s$cursor < 1L || s$cursor > nrow(m) ||
      anyNA(m$status) || any(!m$status %in% .session_statuses)) {
    .at_fail("Invalid saved session structure; inspect the original file.", class = "validation", code = "INVALID_CHECKPOINT")
  }
  if (is.null(s$meta$schema_version) && !any(c("entry_id", "export_stem") %in% names(m))) {
    # Row position is the unambiguous identity of an old queue, even for repeats.
    m$entry_id <- vapply(seq_len(nrow(m)), function(i) .new_identity_id("entry"), character(1))
    m$export_stem <- m$entry_id
  }
  .validate_manifest_identity(m)
  s$manifest <- m
  for (i in seq_len(nrow(m))) {
    if (is.null(s$projects[[i]])) next
    p <- s$projects[[i]]
    .validate_project_structure(p)
    if (!is.null(p$meta$entry_id) && !identical(p$meta$entry_id, m$entry_id[i])) {
      .at_abort("Project identity does not match manifest entry.",
                class = "conflict", code = "IDENTITY_MISMATCH", call = NULL)
    }
    p$meta$entry_id <- m$entry_id[i]
    s$projects[[i]] <- p
  }
  s$meta$schema_version <- .persistence_schema
  s
}

# Same-filesystem staging; callers may inject I/O primitives for failure tests.
# Unix rename replaces atomically. Windows uses a recoverable prior-file backup.
.atomic_save_rds <- function(object, path, overwrite = FALSE, platform = .Platform$OS.type,
                             writer = saveRDS, rename = file.rename,
                             call = rlang::caller_env()) {
  .check_string(path, call = call)
  .check_flag(overwrite, call = call)
  exists_abort <- function() {
    .at_abort(c("{.path {path}} already exists.",
                "i" = "Pass {.code overwrite = TRUE} to replace it."),
              class = "io", code = "ALREADY_EXISTS", call = call)
  }
  fail <- function(msg) .at_abort("{msg}", class = "io", code = "WRITE_FAILED", call = call)
  if (file.exists(path) && !overwrite) exists_abort()
  dir <- dirname(path)
  if (!dir.exists(dir) && !dir.create(dir, recursive = TRUE, showWarnings = FALSE)) {
    fail(paste0("Cannot create output directory: ", dir))
  }
  stage <- tempfile(".stage-", tmpdir = dir)
  on.exit(unlink(stage), add = TRUE)
  # A failing writer usually warns ("cannot open compressed file ...") before
  # it errors; fold those warnings into the classified error instead of
  # leaking them, and re-raise them only if the write succeeded.
  warned <- character()
  tryCatch(
    withCallingHandlers(writer(object, stage), warning = function(w) {
      warned <<- c(warned, conditionMessage(w))
      invokeRestart("muffleWarning")
    }),
    error = function(e) {
      fail(paste0("Could not write ", basename(path), ": ",
                  paste(c(conditionMessage(e), warned), collapse = "; ")))
    }
  )
  if (length(warned) > 0L) {
    cli::cli_warn(c("Writing {.path {basename(path)}} raised a warning.", "i" = "{warned}"))
  }
  # Detect incomplete/invalid serialization before any existing file is touched.
  tryCatch(readRDS(stage), error = function(e) {
    fail(paste0("Could not verify ", basename(path), ": ", conditionMessage(e)))
  })
  if (file.exists(path) && !overwrite) exists_abort()
  backup <- NULL
  if (platform == "windows" && file.exists(path)) {
    backup <- tempfile(".previous-", tmpdir = dir)
    if (!isTRUE(rename(path, backup))) fail(paste0("Cannot back up checkpoint for replacement: ", path))
  }
  ok <- tryCatch(isTRUE(rename(stage, path)), error = function(e) FALSE)
  if (!ok) {
    if (!is.null(backup)) {
      restored <- tryCatch(isTRUE(rename(backup, path)), error = function(e) FALSE)
      if (!restored) fail(paste0("Cannot replace checkpoint. Previous valid checkpoint retained at: ", backup))
    }
    fail(paste0("Cannot replace checkpoint: ", path))
  }
  if (!is.null(backup)) unlink(backup)
  invisible(path)
}

.prepare_session <- function(s) {
  s <- .migrate_session(s)
  s$projects <- lapply(s$projects, function(p) if (is.null(p)) NULL else .prepare_project(p))
  s$meta$annotatR_version <- .pkg_version()
  s
}

# Write a complete checkpoint: every project to an immutable generation file,
# then the session manifest that references them, which is the only file
# replaced in place.
.save_checkpoint <- function(candidate, cursor, write = .atomic_save_rds) {
  candidate <- .migrate_session(candidate)
  # Every project in this snapshot gets an immutable generation path. This also
  # captures unsaved edits left on other queue entries when autosave was off.
  generation <- .new_identity_id("checkpoint")
  created <- character()
  published <- FALSE
  on.exit(if (!published) unlink(created), add = TRUE)
  for (i in seq_along(candidate$projects)) {
    p <- candidate$projects[[i]]
    previous <- candidate$manifest$project_path[i]
    if (is.null(p) && !is.na(previous) && nzchar(previous)) {
      p <- at_load_project(previous)
      if (!is.null(p$meta$entry_id) && !identical(p$meta$entry_id, candidate$manifest$entry_id[i])) {
        .at_abort("Project identity does not match manifest entry.",
                  class = "conflict", code = "IDENTITY_MISMATCH", call = NULL)
      }
      p$meta$entry_id <- candidate$manifest$entry_id[i]
      candidate$projects[[i]] <- p
    }
    if (is.null(p)) next
    path <- file.path(candidate$out_dir, "projects",
                      paste0(candidate$manifest$export_stem[i], "-", generation, ".rds"))
    write(.prepare_project(p), path, overwrite = FALSE)
    created <- c(created, path)
    candidate$manifest$project_path[i] <- path
  }
  persisted <- .prepare_session(candidate)
  # All manifest references are complete before the only mutable file publishes.
  write(persisted, file.path(candidate$out_dir, "_session.rds"), overwrite = TRUE)
  published <- TRUE
  candidate
}

#' Inspect a saved checkpoint without modifying it
#'
#' Validate a saved project or session file and report the state of its image
#' sources, without repairing anything or reading pixels.
#'
#' @param path A saved project or session RDS file.
#' @return A list with `valid` (logical), `class` (the saved object's class),
#'   `issues` (character; why the file is invalid or ambiguous) and `sources`
#'   (one [at_inspect_source()] report per stored project). Invalid or
#'   ambiguous structures are reported without guessing repairs.
#' @family io
#' @seealso [at_inspect_source()], [at_load_session()]
#' @export
at_inspect_saved <- function(path) {
  .check_file(path)
  obj <- tryCatch(readRDS(path), error = identity)
  if (inherits(obj, "error")) {
    return(list(valid = FALSE, class = NULL, issues = conditionMessage(obj), sources = list()))
  }
  result <- tryCatch({
    if (inherits(obj, "annot_session")) {
      .migrate_session(obj)
    } else if (inherits(obj, "annot_project")) {
      .validate_project_structure(obj)
    } else {
      .at_fail("Not a hyperannotatR project or session.", class = "validation", code = "INVALID_CHECKPOINT")
    }
    NULL
  }, error = function(e) conditionMessage(e))
  projects <- if (inherits(obj, "annot_session")) obj$projects else list(obj)
  sources <- lapply(projects, function(p) {
    if (is.null(p)) return(NULL)
    tryCatch(at_inspect_source(p),
             error = function(e) list(status = "unresolved", issue = conditionMessage(e)))
  })
  list(valid = is.null(result), class = class(obj)[1], issues = result %||% character(),
       sources = sources)
}
