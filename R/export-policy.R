# Derived filenames share one conservative, portable policy. Display labels
# stay in projects, mask legends and receipts; they are never interpreted as
# paths. Exports are planned as whole bundles (an output plus its sidecars),
# staged next to their destination and published together.

.export_component <- function(x) {
  x <- gsub("[^A-Za-z0-9_-]", "_", enc2utf8(x))
  x <- substr(x, 1L, 100L)
  x[!nzchar(x)] <- "export"
  reserved <- grepl("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$", x, ignore.case = TRUE)
  x[reserved] <- paste0("_", x[reserved])
  x
}

.export_exists <- function(path) {
  link <- Sys.readlink(path)
  file.exists(path) | (!is.na(link) & nzchar(link))
}

# The caller-selected root may itself resolve through a link. Descendants must
# not: reject even an internal symlink to avoid aliases and changing targets.
.export_preflight <- function(root, paths) {
  .check_string(root)
  root <- normalizePath(root, winslash = "/", mustWork = FALSE)
  for (path in paths) {
    relative <- substring(path, nchar(root) + 2L)
    if (!startsWith(path, paste0(root, "/")) ||
        any(strsplit(relative, "/", fixed = TRUE)[[1]] %in% c("..", ".", ""))) {
      .at_fail("Export containment violation: ", path, class = "io", code = "PATH_OUTSIDE_ROOT")
    }
    components <- strsplit(relative, "/", fixed = TRUE)[[1]]
    current <- root
    for (part in components) {
      current <- file.path(current, part)
      link <- Sys.readlink(current)
      if (!is.na(link) && nzchar(link)) {
        .at_fail("Symlink violates export containment: ", current, class = "io", code = "PATH_OUTSIDE_ROOT")
      }
      if (file.exists(current) && !identical(current, path) && !dir.exists(current)) {
        .at_fail("Export parent is not a directory: ", current, class = "io", code = "INVALID_PATH")
      }
    }
    if (dir.exists(path)) .at_fail("Export target is a directory: ", path, class = "io", code = "INVALID_PATH")
  }
  if (anyDuplicated(tolower(paths))) .at_fail("Export output paths collide or alias.", class = "validation", code = "PATH_COLLISION")
  invisible(paths)
}

# Allocate whole bundles, reserving receipts before any files are written. Each
# job is a list with `stem`, `ext`, optional `subdir` and `sidecar`; the plan
# adds `paths` (the output, then its legend sidecar). Case-folded collisions get
# deterministic `-2`, `-3`, ... suffixes.
.export_plan <- function(dir, jobs, reserved = character()) {
  if (!dir.exists(dir) && !dir.create(dir, recursive = TRUE, showWarnings = FALSE)) {
    .at_fail("Cannot create export directory: ", dir, class = "io", code = "WRITE_FAILED")
  }
  root <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  used <- tolower(file.path(root, reserved))
  for (i in seq_along(jobs)) {
    j <- jobs[[i]]
    stem <- .export_component(j$stem)
    suffix <- ""
    k <- 1L
    repeat {
      parent <- if (is.null(j$subdir) || !nzchar(j$subdir)) root else file.path(root, j$subdir)
      path <- file.path(parent, paste0(stem, suffix, j$ext))
      paths <- c(path, if (isTRUE(j$sidecar)) paste0(path, ".legend.json"))
      if (!any(tolower(paths) %in% used)) break
      k <- k + 1L
      suffix <- paste0("-", k)
    }
    jobs[[i]]$paths <- paths
    used <- c(used, tolower(paths))
  }
  all_paths <- c(unlist(lapply(jobs, `[[`, "paths"), use.names = FALSE), file.path(root, reserved))
  .export_preflight(root, all_paths)
  # Only after the complete plan has passed may descendant directories appear.
  for (d in unique(dirname(all_paths))) {
    if (!dir.exists(d) && !dir.create(d, recursive = TRUE, showWarnings = FALSE)) {
      .at_fail("Cannot create export directory: ", d, class = "io", code = "WRITE_FAILED")
    }
  }
  jobs
}

# Stage every member before replacing any destination; roll back an interrupted
# publication. Multiple renames are not a cross-file atomic transaction. Callers
# must serialize writers and avoid concurrently changing destination symlinks.
.export_bundle <- function(paths, writer, overwrite = FALSE, rename = file.rename) {
  .check_flag(overwrite)
  if (anyDuplicated(tolower(normalizePath(paths, winslash = "/", mustWork = FALSE)))) {
    .at_fail("Export bundle paths collide or alias.", class = "validation", code = "PATH_COLLISION")
  }
  if (any(dir.exists(paths))) .at_fail("Export target is a directory.", class = "io", code = "INVALID_PATH")
  links <- Sys.readlink(paths)
  if (any(!is.na(links) & nzchar(links))) .at_fail("Symlink export targets are not supported.", class = "io", code = "PATH_OUTSIDE_ROOT")
  if (any(.export_exists(paths)) && !overwrite) {
    .at_fail("Export bundle already exists; pass overwrite = TRUE to replace it.", class = "io", code = "ALREADY_EXISTS")
  }
  for (d in unique(dirname(paths))) {
    if (!dir.exists(d) && !dir.create(d, recursive = TRUE, showWarnings = FALSE)) {
      .at_fail("Cannot create output directory: ", d, class = "io", code = "WRITE_FAILED")
    }
  }
  stage <- vapply(paths, function(p) {
    tempfile(".export-stage-", tmpdir = dirname(p), fileext = paste0(".", tools::file_ext(p)))
  }, character(1))
  backup <- rep(NA_character_, length(paths))
  published <- rep(FALSE, length(paths))
  on.exit(unlink(stage), add = TRUE)
  writer(stage)
  sizes <- as.double(file.info(stage)$size)
  if (anyNA(sizes) || any(sizes <= 0) || any(dir.exists(stage))) {
    .at_fail("Incomplete export: every staged file must exist and be nonempty.", class = "io", code = "WRITE_FAILED")
  }
  if (any(.export_exists(paths)) && !overwrite) .at_fail("Export bundle already exists.", class = "io", code = "ALREADY_EXISTS")
  failure <- tryCatch({
    for (i in seq_along(paths)) {
      if (.export_exists(paths[i])) {
        backup[i] <- tempfile(".export-previous-", tmpdir = dirname(paths[i]))
        if (!isTRUE(rename(paths[i], backup[i]))) .at_fail("Cannot back up export: ", paths[i], class = "io", code = "WRITE_FAILED")
      }
    }
    for (i in seq_along(paths)) {
      if (!isTRUE(rename(stage[i], paths[i]))) .at_fail("Cannot publish export: ", paths[i], class = "io", code = "WRITE_FAILED")
      published[i] <- TRUE
    }
    NULL
  }, error = identity)
  if (inherits(failure, "error")) {
    unlink(paths[published])
    retained <- character()
    for (i in which(!is.na(backup) & file.exists(backup))) {
      if (!isTRUE(tryCatch(rename(backup[i], paths[i]), error = function(e) FALSE))) {
        retained <- c(retained, backup[i])
      }
    }
    if (length(retained)) {
      .at_fail(conditionMessage(failure), "; prior files retained at: ",
               paste(retained, collapse = ", "), class = "io", code = "WRITE_FAILED")
    }
    # Re-raise the writer's own condition, keeping its class.
    rlang::cnd_signal(failure)
  }
  unlink(backup[!is.na(backup)])
  invisible(sizes)
}

# One receipt outcome: "ok" for a published bundle, "skipped" for a protected
# existing bundle, "error" (with the message) otherwise.
.export_outcome <- function(paths, writer, overwrite = FALSE) {
  if (any(.export_exists(paths)) && !overwrite) {
    return(list(status = "skipped", message = "Output bundle already exists.",
                bytes = NA_real_, sidecar_bytes = NA_real_))
  }
  tryCatch({
    sizes <- .export_bundle(paths, writer, overwrite)
    list(status = "ok", message = "", bytes = sizes[1],
         sidecar_bytes = if (length(sizes) > 1L) sizes[2] else NA_real_)
  }, error = function(e) {
    list(status = "error", message = conditionMessage(e), bytes = NA_real_, sidecar_bytes = NA_real_)
  })
}

.export_formats <- function(formats, call = rlang::caller_env()) {
  choices <- c("mask_tiff", "geojson", "qupath", "rds", "csv")
  if (!is.character(formats) || length(formats) == 0L || anyNA(formats) ||
      any(!formats %in% choices) || anyDuplicated(formats)) {
    .check_abort(
      c("Export formats must be unique supported format names.",
        "i" = "Choose from {.val {choices}}."),
      call = call
    )
  }
  formats
}

.export_project_file <- function(project, format, paths, level = 0L, mask_type = "labelled",
                                 overlap = "last") {
  switch(format,
    mask_tiff = {
      m <- at_mask(project, type = mask_type, level = level, overlap = overlap)
      at_write_mask(m, paths[1], legend = FALSE)
      .write_legend_json(m, paths[2])
    },
    geojson = at_write_geojson(project, paths[1], level = level),
    qupath = at_write_qupath(project, paths[1], level = level),
    rds = at_save_project(project, paths[1]),
    csv = at_write_rois_csv(project, paths[1])
  )
}

.export_receipt <- function() {
  tibble::tibble(entry_id = character(), image = character(), format = character(),
                 path = character(), bytes = double(), n_rois = integer(),
                 status = character(), message = character(), sidecar_path = character(),
                 sidecar_bytes = double())
}

# Receipts remain available to the caller even if their own publication fails.
.export_receipt_files <- function(receipt, dir, summary = NULL) {
  paths <- file.path(dir, c("_export_manifest.csv", if (!is.null(summary)) "_annotation_summary.csv"))
  error <- tryCatch({
    .export_bundle(paths, function(stage) {
      utils::write.csv(receipt, stage[1], row.names = FALSE)
      if (!is.null(summary)) utils::write.csv(summary, stage[2], row.names = FALSE)
    }, overwrite = TRUE)
    NULL
  }, error = function(e) conditionMessage(e))
  attr(receipt, "receipt_error") <- error
  if (!is.null(error)) cli::cli_warn("Could not publish export receipt: {error}")
  receipt
}
