# The qupflowR handoff: a new, self-contained directory with neutral files
# (QuPath GeoJSON, GeoJSON, integer masks with legends, optional NPY/CSV/RDS),
# a manifest and a SHA-256 inventory, plus the local stage -> commit flow that
# applies a partner's changes to a hyperannotatR project only after an explicit,
# revision-checked, idempotent commit.

.handoff_formats <- c("qupath_geojson", "geojson", "mask_tiff", "mask_npy", "csv", "rds", "manifest")

# ---- Inventory ---------------------------------------------------------------

# All regular files below `dir` (relative, forward slashes), including hidden
# files, excluding `integrity.json` at the root.
.list_payload_files <- function(dir) {
  files <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE,
                      include.dirs = FALSE)
  files <- gsub("\\\\", "/", files)
  files[files != "integrity.json"]
}

# Every entry below `dir`, directories included, so a symbolic link to a
# directory is seen even when listing does not descend into it.
.list_payload_entries <- function(dir) {
  entries <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE,
                        include.dirs = TRUE)
  gsub("\\\\", "/", entries)
}

# Operating-system metadata files a file manager may drop into any directory
# it shows (Finder's .DS_Store and AppleDouble ._* files, Windows Explorer's
# Thumbs.db and desktop.ini). They are never read by hyperannotatR.
.is_os_metadata <- function(path) {
  base <- basename(path)
  base %in% c(".DS_Store", "Thumbs.db", "desktop.ini") | startsWith(base, "._")
}

.build_integrity <- function(dir) {
  files <- .list_payload_files(dir)
  files <- files[order(.utf8_sort_key(files), method = "radix")]
  list(
    format_version = .contract$integrity_format,
    files = lapply(files, function(f) {
      full <- file.path(dir, f)
      list(path = f, size_bytes = as.numeric(file.info(full)$size), sha256 = .sha256_file(full))
    })
  )
}

.handoff_digest <- function(integrity) .digest_json(integrity)

# ---- Export --------------------------------------------------------------------

# Write the neutral files for one project into `dir`; return file and mask
# records relative to `root`.
.export_project_files <- function(project, dir, root, formats, level, mask_type, entry_id) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  rel <- function(p) .relative_to(p, root)
  files <- list()
  masks <- list()
  add_file <- function(path, format, role) {
    files[[length(files) + 1L]] <<- list(path = rel(path), format = format, role = role,
                                         entry_id = entry_id)
  }
  # The image record hashes the real source; every written file comes from a
  # copy without local paths, so no absolute path reaches the handoff (mask
  # legend sidecars, for example, record the image's source descriptor).
  img_rec <- .image_record(project$image)
  safe <- .strip_local_paths(project)
  .write_json_atomic(img_rec, file.path(dir, "image.json"))
  add_file(file.path(dir, "image.json"), "image_json", "image")
  if ("qupath_geojson" %in% formats) {
    p <- file.path(dir, "annotations_qupath.geojson")
    at_write_qupath(safe, p, level = level, dialect = "qupath")
    add_file(p, "qupath_geojson", "annotations")
  }
  if ("geojson" %in% formats) {
    p <- file.path(dir, "annotations.geojson")
    at_write_geojson(safe, p, level = level)
    add_file(p, "geojson", "annotations")
  }
  if (any(c("mask_tiff", "mask_npy") %in% formats) && length(project$layers) > 0L) {
    mdir <- file.path(dir, "masks")
    dir.create(mdir, showWarnings = FALSE)
    stems <- .unique_components(.safe_component(names(project$layers)))
    for (k in seq_along(project$layers)) {
      nm <- names(project$layers)[k]
      m <- at_mask(safe, type = mask_type, layer = nm, level = level)
      mid <- paste0(if (is.na(entry_id)) "project" else entry_id, ":", nm)
      if ("mask_tiff" %in% formats) {
        maxv <- max(as.integer(as.matrix(m)), 0L)
        if (maxv > 65535L) {
          .at_abort(c("Layer {.val {nm}} has mask values up to {maxv}, beyond 16-bit TIFF.",
                      "i" = "Export with {.code formats = \"mask_npy\"} (int32)."),
                    class = "limit", code = "MASK_RANGE")
        }
        p <- file.path(mdir, paste0(stems[k], "_", mask_type, ".tif"))
        at_write_mask(m, p, format = "tiff", bits = if (maxv > 255L) 16L else 8L)
        add_file(p, "mask_tiff", "mask")
        add_file(paste0(p, ".legend.json"), "legend_json", "mask_legend")
        rec <- .mask_record(m, file = rel(p), mask_id = mid)
        rec$dtype <- if (maxv > 255L) "uint16" else "uint8"
        rec$layer <- nm
        masks[[length(masks) + 1L]] <- rec
      }
      if ("mask_npy" %in% formats) {
        p <- file.path(mdir, paste0(stems[k], "_", mask_type, ".npy"))
        at_write_npy(m, p, dtype = "int32")
        add_file(p, "mask_npy", "mask")
        add_file(paste0(p, ".legend.json"), "legend_json", "mask_legend")
        rec <- .mask_record(m, file = rel(p), mask_id = paste0(mid, ":npy"))
        rec$dtype <- "int32"
        rec$layer <- nm
        masks[[length(masks) + 1L]] <- rec
      }
    }
  }
  if ("csv" %in% formats) {
    p <- file.path(dir, "tables", "rois.csv")
    dir.create(dirname(p), showWarnings = FALSE)
    at_write_rois_csv(safe, p)
    add_file(p, "csv", "roi_table")
  }
  if ("rds" %in% formats) {
    p <- file.path(dir, "objects", "project.rds")
    dir.create(dirname(p), showWarnings = FALSE)
    at_save_project(safe, p)
    add_file(p, "rds", "annotatr_internal")
  }
  if (at_is_spectral(project$image)) {
    p <- file.path(dir, "hsi_manifest.json")
    .write_json_atomic(.hsi_manifest(project$image, img_rec), p)
    add_file(p, "hsi_manifest", "hsi")
  }
  list(files = files, masks = masks)
}

# A project copy safe to hand to a partner: no pixel handle or runtime read
# identity, and every absolute path in the image record (source, source
# descriptor and its companion files, reader options, metadata messages)
# reduced to its file name. A loaded copy keeps its annotations and reports
# the source as missing until relinked.
.strip_local_paths <- function(project) {
  img <- project$image
  d <- img$source_descriptor
  paths <- c(img$source, if (is.list(d)) d[["path"]],
             if (is.list(d) && is.list(d[["files"]])) vapply(d[["files"]], function(f) .json_chr(f[["path"]]), character(1)))
  paths <- paths[!is.na(paths) & .is_absolute_path(paths)]
  dirs <- unique(dirname(paths))
  img$handle <- NULL
  img$read_key <- NULL
  img$reader <- NULL
  img$read_generation <- NULL
  img$source <- basename(img$source)
  if (is.list(d)) img$source_descriptor <- .scrub_paths(d, dirs)
  if (is.list(img$meta)) {
    img$meta$source_error <- NULL
    img$meta <- .scrub_paths(img$meta, dirs)
  }
  project$image <- img
  project
}

.is_absolute_path <- function(x) grepl("^(/|~|[A-Za-z]:[/\\\\]|\\\\\\\\)", x)

# Replace absolute paths in the character values of a nested list by their
# file names, and remove the given directories from other strings. List
# structure and attributes are kept.
.scrub_paths <- function(x, dirs = character()) {
  if (is.character(x)) {
    keep <- attributes(x)
    hit <- !is.na(x) & .is_absolute_path(x)
    x[hit] <- basename(x[hit])
    for (d in dirs[nzchar(dirs) & dirs != "/" & dirs != "."]) {
      x <- gsub(paste0(d, "/"), "", x, fixed = TRUE)
      x <- gsub(d, "", x, fixed = TRUE)
    }
    attributes(x) <- keep
    return(x)
  }
  if (is.list(x)) {
    for (i in seq_along(x)) {
      if (!is.null(x[[i]])) x[[i]] <- .scrub_paths(x[[i]], dirs)
    }
  }
  x
}

.hsi_manifest <- function(img, img_rec = .image_record(img)) {
  list(
    schema = .contract$hsi,
    schema_version = .contract$version,
    document = "hsi_manifest",
    cube_id = img_rec$image_id,
    source_files = img_rec$source_files,
    tile_contract = "[y, x, band]",
    width = img_rec$width, height = img_rec$height, n_bands = img_rec$n_bands,
    n_levels = img_rec$n_levels, dtype = img_rec$dtype,
    bands = img_rec$bands,
    hsi = img_rec$hsi,
    plane = img_rec$plane,
    series_id = img_rec$series_id,
    pixel_size = img_rec$pixel_size, pixel_unit = img_rec$pixel_unit,
    calibration_digest = img_rec$calibration_digest,
    transform_digest = img_rec$transform_digest,
    read_accounting = at_read_stats(img)[c("tiles", "file_bytes", "decoded_bytes",
                                           "max_tile_bytes", "window_read")],
    note = "Native vendor cubes are referenced by digest and role, never embedded."
  )
}

#' Export annotations as a qupflowR handoff directory
#'
#' Write a new, self-contained handoff directory for a partner package such as
#' qupflowR. It contains only neutral, relative files: `image.json`,
#' `annotations_qupath.geojson` (QuPath 0.4+ dialect), optionally
#' `annotations.geojson`, one integer mask per layer under `masks/` with a
#' `.legend.json` sidecar, optional `tables/rois.csv`, an optional
#' hyperannotatR-internal `objects/project.rds`, `hsi_manifest.json` for spectral
#' images, `manifest.json` ([at_interop_manifest()]) and `integrity.json`, the
#' SHA-256 inventory of every other file. The handoff digest is the SHA-256 of
#' the canonical `integrity.json`. Absolute paths are never used as identity.
#'
#' Files are written into a hidden sibling staging directory and moved into
#' place only when complete, so a failed export never leaves a directory that
#' looks valid. An existing destination is replaced only with
#' `overwrite = TRUE`, and only when it is itself a handoff directory; if the
#' new directory cannot be moved into place the previous one is restored. The
#' optional `objects/project.rds` holds no pixels, read identity or local path
#' (the image source is reduced to its file name).
#'
#' @param x An [annot_project] or [annot_session] (materialised entries are
#'   exported under `entries/<entry_id>/`, where `entry_id` is the session's
#'   stable entry id, or `entry-NNNN` by queue position for sessions without
#'   stable ids).
#' @param destination Path of the handoff directory to create.
#' @param formats Any of `"qupath_geojson"`, `"geojson"`, `"mask_tiff"`,
#'   `"mask_npy"`, `"csv"`, `"rds"`, `"manifest"`. `manifest.json` and
#'   `integrity.json` are always written.
#' @param overwrite Logical; replace an existing handoff directory.
#' @param level Integer pyramid level for coordinates and masks. Default `0`.
#' @param mask_type Mask type for mask files: `"labelled"` (default; one value
#'   per ROI, joinable by `roi_id` through the legend), `"multiclass"` or
#'   `"binary"`.
#' @param scope For sessions: `"all"` materialised entries (default),
#'   `"current"` or `"complete"`.
#' @param call The calling environment, for error reporting.
#'
#' @return An `at_handoff_receipt` (invisibly): a list with `destination`,
#'   `handoff_digest`, `files` (a tibble of `path`, `size_bytes`, `sha256`,
#'   `format`, `role`, `entry_id`), `manifest`, `skipped` entries and
#'   `overwritten`.
#' @family interop
#' @seealso [at_import_qupflowr()], [at_interop_manifest()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE)
#' dest <- file.path(tempdir(), "handoff-example")
#' rc <- at_export_qupflowr(at_example_project(), dest, overwrite = TRUE)
#' rc$handoff_digest
#' rc$files[, c("path", "format")]
at_export_qupflowr <- function(x, destination,
                               formats = c("qupath_geojson", "mask_tiff", "manifest"),
                               overwrite = FALSE, level = 0L,
                               mask_type = c("labelled", "multiclass", "binary"),
                               scope = c("all", "current", "complete"),
                               call = rlang::caller_env()) {
  if (!inherits(x, c("annot_project", "annot_session"))) {
    .at_abort("{.arg x} must be an {.cls annot_project} or {.cls annot_session}.", call = call)
  }
  .check_string(destination, call = call)
  .check_flag(overwrite, call = call)
  level <- .check_count(level, call = call)
  # Resolve omitted choice arguments to their first value here, so the
  # validator only ever sees what the caller actually passed.
  if (missing(mask_type)) mask_type <- mask_type[[1]]
  if (missing(scope)) scope <- scope[[1]]
  mask_type <- .check_choice(mask_type, c("labelled", "multiclass", "binary"), call = call)
  scope <- .check_choice(scope, c("all", "current", "complete"), call = call)
  if (!is.character(formats) || length(formats) == 0L || !all(formats %in% .handoff_formats)) {
    .at_abort("{.arg formats} must be drawn from {.val {(.handoff_formats)}}.", call = call)
  }
  dest <- normalizePath(destination, winslash = "/", mustWork = FALSE)
  existed <- file.exists(dest)
  if (existed) {
    if (!overwrite) {
      .at_abort(c("{.path {destination}} already exists.",
                  "i" = "Choose a new handoff directory or pass {.code overwrite = TRUE}."),
                class = "io", code = "DESTINATION_EXISTS", call = call)
    }
    if (!dir.exists(dest) || !file.exists(file.path(dest, "integrity.json"))) {
      .at_abort(c("{.path {destination}} is not a hyperannotatR handoff directory.",
                  "x" = "Refusing to replace a directory or file without {.file integrity.json}."),
                class = "io", code = "DESTINATION_NOT_HANDOFF", call = call)
    }
  }
  parent <- dirname(dest)
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  stage <- file.path(parent, paste0(".", basename(dest), ".partial-", .random_hex(6L, secure = FALSE)))
  dir.create(stage)
  ok <- FALSE
  on.exit(if (!ok) unlink(stage, recursive = TRUE), add = TRUE)

  files <- list()
  masks <- list()
  skipped <- character()
  if (inherits(x, "annot_project")) {
    res <- .export_project_files(x, stage, stage, formats, level, mask_type, NA_character_)
    files <- res$files
    masks <- res$masks
  } else {
    m <- x$manifest
    idx <- switch(scope, all = seq_len(nrow(m)), current = x$cursor,
                  complete = which(m$status == "complete"))
    for (i in idx) {
      eid <- .session_entry_id(x, i)
      p <- x$projects[[i]]
      if (is.null(p)) {
        skipped <- c(skipped, eid)
        next
      }
      res <- .export_project_files(p, file.path(stage, "entries", eid), stage, formats, level,
                                   mask_type, eid)
      files <- c(files, res$files)
      masks <- c(masks, res$masks)
    }
  }
  manifest <- unclass(at_interop_manifest(x, call = call))
  manifest$masks <- masks
  manifest$files <- files
  manifest$provenance$export <- list(formats = as.list(formats), level = level,
                                     mask_type = mask_type, scope = scope,
                                     skipped_entries = as.list(skipped))
  .schema_assert(.as_json_value(manifest), .contract$handoff, "manifest", what = "manifest",
                 call = call)
  .write_json_atomic(manifest, file.path(stage, "manifest.json"))
  integrity <- .build_integrity(stage)
  .write_json_atomic(integrity, file.path(stage, "integrity.json"))
  digest <- .handoff_digest(integrity)

  .replace_dir(stage, dest, what = "handoff", call = call)
  ok <- TRUE
  fmt <- vapply(integrity$files, function(f) {
    hit <- Filter(function(r) identical(r$path, f$path), files)
    if (length(hit)) hit[[1]]$format else if (f$path == "manifest.json") "manifest" else "other"
  }, character(1))
  receipt <- structure(list(
    destination = dest,
    handoff_digest = digest,
    files = tibble::tibble(
      path = vapply(integrity$files, `[[`, character(1), "path"),
      size_bytes = vapply(integrity$files, function(f) as.numeric(f$size_bytes), numeric(1)),
      sha256 = vapply(integrity$files, `[[`, character(1), "sha256"),
      format = fmt
    ),
    manifest = manifest,
    skipped = skipped,
    overwritten = existed
  ), class = "at_handoff_receipt")
  invisible(receipt)
}

#' @export
print.at_handoff_receipt <- function(x, ...) {
  cat(cli::format_inline("{.cls at_handoff_receipt} {.path {x$destination}}"), "\n", sep = "")
  cat("  files: ", nrow(x$files), "  |  digest: ", x$handoff_digest, "\n", sep = "")
  if (length(x$skipped)) cat("  skipped entries: ", paste(x$skipped, collapse = ", "), "\n", sep = "")
  invisible(x)
}

# ---- Verification ---------------------------------------------------------------

.check_row <- function(check, status, detail = "") {
  tibble::tibble(check = check, status = status, detail = detail)
}

# Verify a handoff directory: inventory, hashes, extra/missing/duplicate files,
# symlinks (files and directories), manifest major version and schema, and
# that every file the manifest references is a clean relative path listed in
# the verified inventory. Unlisted operating-system metadata files
# (.DS_Store, ._*, Thumbs.db, desktop.ini) are ignored with a warning; any
# other integrity, version or schema failure aborts with a classified
# `at_error`. Returns the parsed documents and a checks table.
.verify_handoff <- function(dir, call = rlang::caller_env()) {
  dir <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  checks <- list()
  fail <- function(msg, code, details = list()) {
    .at_abort(msg, code = code, details = details, call = call)
  }
  ipath <- file.path(dir, "integrity.json")
  if (!file.exists(ipath)) {
    fail("The handoff has no {.file integrity.json}.", "INTEGRITY_MISSING")
  }
  integrity <- .read_json_doc(ipath, max_bytes = .interop_limits()$handoff_max_json_bytes, call = call)
  # A well-formed but unsupported major version is a protocol mismatch, not
  # a schema violation, so check it before the 1.x schema.
  fv <- integrity[["format_version"]]
  if (.is_string(fv) && grepl("^[0-9]+\\.[0-9]+$", fv)) {
    .check_major_version(fv, 1L, "integrity", call = call)
  }
  .schema_assert(integrity, .contract$handoff, "integrity", what = "integrity", call = call)
  .check_major_version(integrity[["format_version"]], 1L, "integrity", call = call)
  listed <- vapply(integrity[["files"]], `[[`, character(1), "path")
  if (length(listed) > .interop_limits()$handoff_max_files) {
    .at_abort("The handoff lists more files than the limit.", class = "limit",
              code = "PAYLOAD_TOO_LARGE", call = call)
  }
  if (anyDuplicated(listed)) {
    fail("The inventory lists {.val {unique(listed[duplicated(listed)])}} more than once.",
         "INTEGRITY_DUPLICATE")
  }
  if (!identical(listed, listed[order(.utf8_sort_key(listed), method = "radix")])) {
    fail("The inventory is not sorted by UTF-8 path.", "INTEGRITY_INVALID")
  }
  bad <- listed[!vapply(listed, .is_clean_relative, logical(1))]
  if (length(bad)) {
    fail("The inventory contains paths outside the handoff.", "PATH_OUTSIDE_ROOT")
  }
  entries <- .list_payload_entries(dir)
  links <- entries[.is_symlink(file.path(dir, entries))]
  if (length(links)) {
    fail("The handoff contains symbolic links: {.val {links}}.", "INTEGRITY_SYMLINK")
  }
  actual <- .list_payload_files(dir)
  extra <- setdiff(actual, listed)
  ignored <- extra[.is_os_metadata(extra)]
  extra <- setdiff(extra, ignored)
  missing <- setdiff(listed, actual)
  if (length(missing)) {
    fail("Files listed in the inventory are missing: {.val {missing}}.", "INTEGRITY_MISSING",
         list(missing = as.list(missing)))
  }
  if (length(extra)) {
    fail("Files not listed in the inventory are present: {.val {extra}}.", "INTEGRITY_EXTRA",
         list(extra = as.list(extra)))
  }
  for (f in integrity[["files"]]) {
    full <- file.path(dir, f[["path"]])
    size <- file.info(full)$size
    if (!isTRUE(size == f[["size_bytes"]])) {
      fail("{.file {f[['path']]}} has {size} bytes; the inventory says {f[['size_bytes']]}.",
           "INTEGRITY_MISMATCH", list(path = f[["path"]]))
    }
    if (!identical(.sha256_file(full), f[["sha256"]])) {
      fail("{.file {f[['path']]}} does not match its SHA-256 in the inventory.", "INTEGRITY_MISMATCH",
           list(path = f[["path"]]))
    }
  }
  checks[[length(checks) + 1L]] <- .check_row("integrity", "ok",
                                              sprintf("%d files verified", length(listed)))
  if (length(ignored)) {
    checks[[length(checks) + 1L]] <- .check_row(
      "os_metadata", "warn",
      sprintf("ignored %d unlisted operating-system metadata file(s): %s", length(ignored),
              paste(ignored, collapse = ", "))
    )
  }
  if (!"manifest.json" %in% listed) {
    fail("The handoff has no {.file manifest.json}.", "MANIFEST_MISSING")
  }
  manifest <- .read_json_doc(file.path(dir, "manifest.json"),
                             max_bytes = .interop_limits()$handoff_max_json_bytes, call = call)
  if (!identical(manifest[["schema"]], .contract$handoff)) {
    .at_abort("{.file manifest.json} is not an {.val {(.contract$handoff)}} document.",
              class = "protocol", code = "PROTOCOL_MISMATCH", call = call)
  }
  .check_major_version(manifest[["schema_version"]], 1L, "manifest", call = call)
  .schema_assert(manifest, .contract$handoff, "manifest", what = "manifest", call = call)
  refs <- c(
    vapply(manifest[["files"]] %||% list(), function(f) .json_chr(f[["path"]]), character(1)),
    vapply(manifest[["masks"]] %||% list(), function(m) .json_chr(m[["file"]]), character(1))
  )
  refs <- unique(refs[!is.na(refs)])
  outside <- refs[!vapply(refs, .is_clean_relative, logical(1))]
  if (length(outside)) {
    fail("The manifest references paths outside the handoff: {.val {outside}}.", "PATH_OUTSIDE_ROOT",
         list(paths = as.list(outside)))
  }
  unlisted <- setdiff(refs, listed)
  if (length(unlisted)) {
    fail("The manifest references files missing from the verified inventory: {.val {unlisted}}.",
         "INTEGRITY_MISSING", list(missing = as.list(unlisted)))
  }
  checks[[length(checks) + 1L]] <- .check_row("manifest_schema", "ok", manifest[["schema_version"]])
  list(dir = dir, integrity = integrity, manifest = manifest,
       digest = .handoff_digest(integrity), checks = do.call(rbind, checks))
}

# ---- Import ---------------------------------------------------------------------

# A JSON value as a single string; `default` for null/missing.
.json_chr <- function(v, default = NA_character_) {
  if (is.null(v) || length(v) != 1L || is.na(v)) default else as.character(v)
}

# Is a parsed JSON document GeoJSON features: a Feature, a FeatureCollection
# or a (possibly empty) bare array of Features?
.is_geojson_doc <- function(doc) {
  if (!is.list(doc)) {
    return(FALSE)
  }
  if (!is.null(names(doc))) {
    return(identical(doc[["type"]], "FeatureCollection") || identical(doc[["type"]], "Feature"))
  }
  all(vapply(doc, function(f) is.list(f) && identical(f[["type"]], "Feature"), logical(1)))
}

# The id each feature of a GeoJSON document carries itself (NA when it has
# none): the hyperannotatR id in QuPath metadata or the GeoJSON roi_id property,
# then the feature id. Features without one get ids minted by the reader;
# those must never be joined to existing ROIs.
.feature_source_ids <- function(doc, qupath) {
  feats <- tryCatch(.qupath_features(doc), error = function(e) list())
  vapply(feats, function(ft) {
    props <- .jget(ft, "properties") %||% list()
    id <- if (qupath) {
      .jget(props, "metadata", "annotatr_roi_id") %||% .jget(props, "metadata", "annotatR_roi_id") %||%
        .jget(ft, "id")
    } else {
      .jget(props, "roi_id") %||% .jget(ft, "id")
    }
    .json_chr(id)
  }, character(1))
}

# Read the source ids of a GeoJSON file and refuse repeated ones instead of
# letting the reader silently re-mint them.
.checked_source_ids <- function(path, qupath, call) {
  doc <- tryCatch(jsonlite::read_json(path, simplifyVector = FALSE), error = function(e) NULL)
  src <- .feature_source_ids(doc, qupath)
  given <- src[!is.na(src)]
  if (anyDuplicated(given)) {
    .at_abort("{.file {basename(path)}} gives several features the id {.val {unique(given[duplicated(given)])}}.",
              code = "DUPLICATE_ID", call = call)
  }
  src
}

.detect_import_format <- function(file) {
  if (dir.exists(file)) {
    return("handoff")
  }
  base <- tolower(basename(file))
  if (base %in% c("manifest.json", "integrity.json")) {
    return("handoff")
  }
  ext <- tolower(tools::file_ext(file))
  if (ext %in% c("geojson", "json")) {
    doc <- tryCatch(jsonlite::read_json(file, simplifyVector = FALSE),
                    error = function(e) structure(list(), class = "at_json_parse_failure"))
    if (inherits(doc, "at_json_parse_failure")) {
      return("invalid_json")
    }
    if (!.is_geojson_doc(doc)) {
      return("unknown")
    }
    feats <- tryCatch(.qupath_features(doc), error = function(e) list())
    props <- if (length(feats)) .jget(feats[[1]], "properties") else NULL
    if (!is.null(props[["objectType"]]) || !is.null(props[["object_type"]]) ||
        !is.null(props[["classification"]])) {
      return("qupath_geojson")
    }
    return("geojson")
  }
  if (ext %in% c("tif", "tiff", "png")) return("mask")
  if (ext == "npy") return("npy")
  if (ext == "rds") return("rds")
  "unknown"
}

# Group a QuPath layer's ROIs into hyperannotatR layers using the manifest (by ROI
# id) or the hyperannotatR metadata written into the QuPath dialect.
.split_qupath_layers <- function(qlayer, manifest_layers = list(), manifest_rois = list()) {
  roi_layer <- stats::setNames(vapply(manifest_rois, function(r) .json_chr(r[["layer"]]), character(1)),
                               vapply(manifest_rois, function(r) .json_chr(r[["roi_id"]]), character(1)))
  out <- list()
  for (L in manifest_layers) {
    st <- at_style(visible = isTRUE(L[["visible"]]), locked = isTRUE(L[["locked"]]),
                   z = as.integer(L[["z"]] %||% 1L),
                   colour = if (length(L[["colours"]])) unlist(L[["colours"]]) else NULL)
    out[[L[["name"]]]] <- at_layer(L[["name"]], labels = unlist(L[["labels"]]) %||% character(), style = st)
  }
  for (r in qlayer$rois) {
    ln <- roi_layer[r$id]
    if (is.na(ln)) {
      meta <- .jget(r$attributes, "qupath", "metadata")
      ln <- .json_chr(.jget(meta, "annotatr_layer") %||% .jget(meta, "annotatR_layer") %||% qlayer$name)
    }
    if (is.null(out[[ln]])) {
      out[[ln]] <- at_layer(ln)
    }
    out[[ln]]$rois <- c(out[[ln]]$rois, list(r))
    if (!r$label %in% out[[ln]]$labels) {
      out[[ln]]$labels <- c(out[[ln]]$labels, r$label)
      out[[ln]]$style$colour <- .resolve_palette(out[[ln]]$labels, out[[ln]]$style$colour)
    }
  }
  out
}

# Mask encoding declared by a manifest record, or inferred from its type for
# records written before hyperannotatR recorded encodings.
.record_encoding <- function(rec) {
  enc <- .json_chr(rec[["encoding"]])
  if (!is.na(enc)) {
    return(enc)
  }
  switch(.json_chr(rec[["mask_type"]], "labelled"),
         binary = "binary",
         multiclass = if (identical(.json_chr(rec[["overlap"]]), "bitor")) "bitfield" else "categorical",
         "instance")
}

# Values of `m` (other than `background`) that the legend codes do not
# explain: absent codes, or for bitfields bits outside every code.
.unexplained_values <- function(m, codes, background, encoding) {
  present <- setdiff(sort(unique(as.integer(m))), as.integer(background))
  if (identical(encoding, "bitfield")) {
    allowed <- Reduce(bitwOr, as.integer(codes), init = 0L)
    return(present[present < 0L | bitwAnd(present, bitwNot(allowed)) != 0L])
  }
  setdiff(present, as.integer(codes))
}

.read_mask_file <- function(dir, rec, call) {
  path <- file.path(dir, rec[["file"]])
  ext <- tolower(tools::file_ext(path))
  m <- if (ext == "npy") .npy_read_matrix(path, call = call) else .read_mask_matrix(path, call)$m
  storage.mode(m) <- "integer"
  if (nrow(m) != rec[["height"]] || ncol(m) != rec[["width"]]) {
    .at_abort("Mask {.file {rec[['file']]}} is {ncol(m)} x {nrow(m)} px; the manifest says {rec[['width']]} x {rec[['height']]}.",
              code = "MASK_DIMENSIONS", call = call)
  }
  encoding <- .record_encoding(rec)
  background <- as.integer(rec[["background"]] %||% 0L)
  legend_vals <- vapply(rec[["legend"]], function(l) as.integer(l[["value"]]), integer(1))
  missing <- .unexplained_values(m, legend_vals, background, encoding)
  if (length(missing)) {
    .at_abort("Mask {.file {rec[['file']]}} contains values {.val {missing}} missing from its legend.",
              code = "LEGEND_INCOMPLETE", call = call)
  }
  lg <- tibble::tibble(
    value = legend_vals,
    label = vapply(rec[["legend"]], function(l) as.character(l[["label"]]), character(1)),
    layer = vapply(rec[["legend"]], function(l) .json_chr(l[["layer"]]), character(1)),
    roi_id = vapply(rec[["legend"]], function(l) .json_chr(l[["roi_id"]]), character(1)),
    n_px = integer(length(legend_vals)),
    colour = vapply(rec[["legend"]], function(l) .json_chr(l[["colour"]], "#5E2C8E"), character(1))
  )
  overlap <- .json_chr(rec[["overlap"]], "last")
  # The mask constructor enforces the semantic contract (codebook, background
  # collisions, binary values, bitfield codes); report a violation with a
  # stable code instead of the constructor's generic error.
  tryCatch(
    .new_annot_mask(m, lg, rec[["level"]], c(rec[["width"]], rec[["height"]]), rec[["mask_type"]],
                    encoding = encoding, background = background, overlap = overlap),
    error = function(e) {
      .at_abort(c("Mask {.file {rec[['file']]}} does not satisfy its manifest record.",
                  "x" = conditionMessage(e)),
                code = "MASK_INVALID", call = call)
    }
  )
}

#' Import a qupflowR handoff or neutral interchange file
#'
#' Read only the neutral contract, validate it, and return a namespaced
#' hyperannotatR result together with a conversion report. For a handoff directory
#' the SHA-256 inventory (missing, extra, duplicate, resized, altered or
#' symlinked files), the manifest schema and major version, ROI id uniqueness
#' and the id join between manifest and GeoJSON, layers, planes, mask
#' dimensions, integer values and legend completeness are all checked. Every
#' file the manifest references must be a clean relative path listed in the
#' verified inventory; unlisted operating-system metadata files (`.DS_Store`,
#' `._*`, `Thumbs.db`, `desktop.ini`) are ignored with a warning. Any failure
#' aborts with a classified `at_error`: `at_validation_error` for integrity,
#' schema and join failures, `at_protocol_error` for an unsupported major
#' version, `at_limit_error` for oversized inventories and `at_io_error` for
#' missing files. Nothing is written, no analysis is started, and foreign
#' objects are never returned as if they were hyperannotatR objects: imported ROIs
#' carry `source = "imported"` and partner fields under
#' `attributes$qupflowr`. Features of a single GeoJSON file that carry no id
#' get a minted one and are flagged (`attributes$qupflowr$id_minted`), so
#' [at_stage_qupflowr()] creates them instead of joining them to an existing
#' ROI; two features with the same id are refused (`DUPLICATE_ID`). Handoff
#' coordinates are read at the export level recorded in the manifest. An RDS
#' file is refused, because deserialising it is not a neutral read.
#'
#' @param file A handoff directory (or its `manifest.json`/`integrity.json`), a
#'   QuPath GeoJSON, a GeoJSON, a mask TIFF/PNG with legend sidecar, or a
#'   `.npy` mask.
#' @param format `"auto"` (default), `"handoff"`, `"qupath_geojson"`,
#'   `"geojson"`, `"mask"` or `"npy"`.
#' @param expected_revision Optional `"sha256:..."` annotation revision the
#'   caller expects the handoff to carry; a different revision aborts with an
#'   `at_conflict_error` (`REVISION_CONFLICT`).
#' @param call The calling environment, for error reporting.
#'
#' @return An `at_import_report`: a list with `status`, `format`,
#'   `source_name`, `handoff_digest`, `manifest`, `checks` (tibble of `check`,
#'   `status`, `detail`), `objects` (`layers`: named list of [annot_layer];
#'   `masks`: named list of `annot_mask`; `images`: image records), `conversion`
#'   (tibble with one row per ROI: `roi_id`, `layer`, `label`,
#'   `source_object_id`, `object_type`, `geometry_fidelity`, `geometry_match`
#'   (`"exact"` bytes, `"equivalent"` within 1e-9 after level normalisation,
#'   `"changed"`, or `NA` without a manifest record), `notes`) and
#'   `annotation_revision` of the imported layers.
#' @family interop
#' @seealso [at_export_qupflowr()], [at_stage_qupflowr()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE)
#' dest <- file.path(tempdir(), "handoff-import-example")
#' at_export_qupflowr(at_example_project(), dest, overwrite = TRUE)
#' rep <- at_import_qupflowr(dest)
#' rep$checks
at_import_qupflowr <- function(file, format = c("auto", "handoff", "qupath_geojson", "geojson",
                                                "mask", "npy"),
                               expected_revision = NULL, call = rlang::caller_env()) {
  .check_string(file, call = call)
  if (!file.exists(file)) {
    .at_abort("{.path {file}} does not exist.", class = "io", code = "FILE_MISSING", call = call)
  }
  if (missing(format)) format <- format[[1]]
  format <- .check_choice(format, c("auto", "handoff", "qupath_geojson", "geojson", "mask", "npy"),
                          call = call)
  if (!is.null(expected_revision)) .check_string(expected_revision, call = call)
  if (format == "auto") {
    format <- .detect_import_format(file)
  }
  if (format == "rds") {
    .at_abort(c("RDS files are not part of the neutral contract.",
                "i" = "Load a trusted hyperannotatR project with {.fn at_load_project} instead."),
              code = "FORMAT_NOT_NEUTRAL", call = call)
  }
  if (format == "invalid_json") {
    .at_abort("{.path {basename(file)}} is not valid JSON.", code = "INVALID_JSON", call = call)
  }
  if (format == "unknown") {
    .at_abort("Cannot determine the interchange format of {.path {basename(file)}}.",
              code = "FORMAT_UNRECOGNISED", call = call)
  }
  report <- switch(
    format,
    handoff = .import_handoff(if (dir.exists(file)) file else dirname(file), call),
    qupath_geojson = .import_single_geojson(file, qupath = TRUE, call),
    geojson = .import_single_geojson(file, qupath = FALSE, call),
    mask = .import_single_mask(file, npy = FALSE, call),
    npy = .import_single_mask(file, npy = TRUE, call)
  )
  report$format <- format
  if (!is.null(expected_revision)) {
    have <- .jget(report$manifest, "annotations", "annotation_revision") %||% report$annotation_revision
    if (!identical(have, expected_revision)) {
      .at_abort(
        c("The handoff carries a different annotation revision than expected.",
          "x" = "Expected {.val {expected_revision}}, found {.val {have}}.",
          "i" = "Re-read the partner state and stage again."),
        class = "conflict", code = "REVISION_CONFLICT",
        details = list(expected = expected_revision, actual = have), call = call
      )
    }
    report$checks <- rbind(report$checks, .check_row("expected_revision", "ok", expected_revision))
  }
  report$status <- if (any(report$checks$status == "warn")) "valid_with_warnings" else "valid"
  structure(report, class = "at_import_report")
}

# Scale an sfc from one level grid to another (`from`, `to` are c(width, height)).
.scale_sfc <- function(geom, from, to) {
  fx <- to[1] / from[1]
  fy <- to[2] / from[2]
  sf::st_sfc(lapply(geom, .apply_coords, fun = function(m) cbind(m[, 1] * fx, m[, 2] * fy)),
             crs = sf::NA_crs_)
}

# Level dimensions c(width, height) recorded for `image_id` in a manifest.
.manifest_level_dims <- function(images, image_id, level) {
  for (im in images %||% list()) {
    if (identical(im[["image_id"]], image_id) && length(im[["level_dims"]]) > level) {
      d <- im[["level_dims"]][[level + 1L]]
      return(c(as.numeric(d[["width"]]), as.numeric(d[["height"]])))
    }
  }
  NULL
}

# Match of an imported ROI against its manifest record. Imported handoff
# coordinates are at the export level; they are scaled to the record's level
# (with the manifest's level dimensions) before the WKB digest is compared.
# A non-power-of-two rescale can differ from the original in the last bits:
# then the result is "equivalent" when the bounding box agrees with the record
# within 1e-9 (relative), otherwise "changed".
.geometry_match <- function(r, rec, images = list()) {
  if (is.null(rec)) {
    return(NA_character_)
  }
  g <- r$geometry
  lv <- as.integer(rec[["level"]] %||% r$level)
  rescaled <- !identical(as.integer(r$level), lv)
  if (rescaled) {
    from <- .manifest_level_dims(images, rec[["image_id"]], as.integer(r$level))
    to <- .manifest_level_dims(images, rec[["image_id"]], lv)
    if (is.null(from) || is.null(to)) {
      return("changed")
    }
    g <- .scale_sfc(g, from, to)
  }
  if (identical(.geometry_sha256(g), rec[["geometry_sha256"]])) {
    return("exact")
  }
  if (rescaled && is.list(rec[["bbox"]])) {
    bb <- as.numeric(sf::st_bbox(g))
    want <- as.numeric(unlist(rec[["bbox"]][c("xmin", "ymin", "xmax", "ymax")]))
    if (length(want) == 4L && all(abs(bb - want) <= 1e-9 * max(1, abs(want)))) {
      return("equivalent")
    }
  }
  "changed"
}

.conversion_rows <- function(layers, manifest_rois = list(), images = list()) {
  by_id <- stats::setNames(manifest_rois, vapply(manifest_rois, function(r) .json_chr(r[["roi_id"]]), character(1)))
  rows <- list()
  for (L in layers) {
    for (r in L$rois) {
      rec <- by_id[[r$id]]
      match <- .geometry_match(r, rec, images)
      notes <- character()
      qp <- .jget(r$attributes, "qupath")
      if (identical(.jget(qp, "roi_native"), "ellipse")) notes <- c(notes, "ellipse polygonised by QuPath")
      if (identical(match, "changed")) notes <- c(notes, "geometry bytes differ from the manifest record")
      rows[[length(rows) + 1L]] <- tibble::tibble(
        roi_id = r$id, layer = L$name, label = r$label,
        source_object_id = .json_chr(.jget(qp, "object_id")),
        object_type = .json_chr(.jget(qp, "object_type")),
        geometry_fidelity = .geometry_fidelity(r),
        geometry_match = match,
        notes = paste(notes, collapse = "; ")
      )
    }
  }
  if (length(rows) == 0L) {
    return(tibble::tibble(roi_id = character(), layer = character(), label = character(),
                          source_object_id = character(), object_type = character(),
                          geometry_fidelity = character(), geometry_match = character(),
                          notes = character()))
  }
  do.call(rbind, rows)
}

# Tag imported ROIs with their provenance. `source_ids` (the ids features
# carry themselves, see .feature_source_ids()) marks ROIs whose id was minted
# by the reader: `attributes$qupflowr$id_minted = TRUE`.
.tag_imported <- function(layers, digest, manifest_rois = list(), source_ids = NULL) {
  by_id <- stats::setNames(manifest_rois, vapply(manifest_rois, function(r) .json_chr(r[["roi_id"]]), character(1)))
  lapply(layers, function(L) {
    L$rois <- lapply(L$rois, function(r) {
      rec <- by_id[[r$id]]
      r$source <- "imported"
      r$attributes$qupflowr <- list(handoff_digest = digest,
                                    source_record = if (is.null(rec)) NULL else rec)
      if (!is.null(source_ids) && !r$id %in% source_ids) {
        r$attributes$qupflowr$id_minted <- TRUE
      }
      if (!is.null(rec)) {
        r$attributes$review_status <- rec[["review_status"]]
        if (isTRUE(rec[["locked"]])) r$attributes$locked <- TRUE
        pl <- .jget(rec, "plane")
        if (is.list(pl)) {
          r$attributes$plane <- list(c = .jget(pl, "c") %||% NA_integer_, z = .jget(pl, "z") %||% 0L,
                                     t = .jget(pl, "t") %||% 0L)
        }
      }
      r
    })
    L
  })
}

# Read a handoff annotation file whose coordinates are all at `level` (a
# handoff is written at one export level whatever level the ROIs were stored
# at). Readers that take `coordinate_level` record it without rescaling and
# without the ambiguity check meant for loose legacy files; the level is then
# set on every ROI in any case. QuPath files return one layer, GeoJSON files a
# named list of layers.
.read_annotations_at <- function(path, qupath, level, call) {
  reader <- if (qupath) at_read_qupath else at_read_geojson
  args <- list(path, call = call)
  if ("coordinate_level" %in% names(formals(reader))) args$coordinate_level <- as.integer(level)
  out <- do.call(reader, args)
  if (qupath) {
    out$rois <- lapply(out$rois, function(r) {
      r$level <- as.integer(level)
      r
    })
    return(out)
  }
  .set_roi_level(out, level)
}

# Record that ROI coordinates are at `level`.
.set_roi_level <- function(layers, level) {
  lapply(layers, function(L) {
    L$rois <- lapply(L$rois, function(r) {
      r$level <- as.integer(level)
      r
    })
    L
  })
}

.import_handoff <- function(dir, call) {
  v <- .verify_handoff(dir, call = call)
  man <- v$manifest
  checks <- v$checks
  files <- man[["files"]] %||% list()
  entries <- unique(vapply(files, function(f) f[["entry_id"]] %||% NA_character_, character(1)))
  if (length(entries) == 0L) entries <- NA_character_
  export_level <- as.integer(.jget(man, "provenance", "export", "level") %||% 0L)
  layers_out <- list()
  masks_out <- list()
  conv <- list()
  m_rois <- .jget(man, "annotations", "rois") %||% list()
  # hyperannotatR >= 0.3.0 records the queue entry of every ROI and layer; older
  # session manifests are joined by image id.
  by_entry <- any(vapply(m_rois, function(r) "entry_id" %in% names(r), logical(1)))
  layers_by_entry <- any(vapply(man[["layers"]] %||% list(), function(l) "entry_id" %in% names(l), logical(1)))
  keys <- vapply(m_rois, function(r) paste(.json_chr(r[["entry_id"]]), r[["roi_id"]], sep = "\r"), character(1))
  if (anyDuplicated(keys) && (by_entry || is.null(man[["session"]]))) {
    ids <- vapply(m_rois, function(r) r[["roi_id"]], character(1))
    .at_abort("The manifest lists duplicate ROI ids {.val {unique(ids[duplicated(keys)])}}.",
              code = "DUPLICATE_ID", call = call)
  }
  for (eid in entries) {
    ef <- Filter(function(f) identical(f[["entry_id"]] %||% NA_character_, eid), files)
    ann <- Filter(function(f) f[["format"]] %in% c("qupath_geojson", "geojson"), ef)
    ann <- ann[order(vapply(ann, function(f) f[["format"]] != "qupath_geojson", logical(1)))]
    key <- if (is.na(eid)) "project" else eid
    e_rois <- if (by_entry) {
      Filter(function(r) identical(.json_chr(r[["entry_id"]]), eid), m_rois)
    } else {
      img_id <- if (length(man[["images"]])) {
        queue <- .jget(man, "session", "queue") %||% list()
        idx <- if (is.na(eid)) 1L else which(vapply(queue, function(q) .json_chr(q[["entry_id"]]), character(1)) == eid)
        q <- if (!is.na(eid) && length(idx)) queue[[idx[1]]] else NULL
        .jget(q, "image_id") %||% .jget(man[["images"]][[1]], "image_id")
      } else NA_character_
      Filter(function(r) identical(r[["image_id"]] %||% NA_character_, img_id) || is.na(img_id), m_rois)
    }
    e_layers <- if (layers_by_entry) {
      Filter(function(l) identical(.json_chr(l[["entry_id"]]), eid), man[["layers"]])
    } else {
      man[["layers"]] %||% list()
    }
    if (length(ann)) {
      f <- ann[[1]]
      path <- file.path(v$dir, f[["path"]])
      qupath <- f[["format"]] == "qupath_geojson"
      src_ids <- .checked_source_ids(path, qupath, call)
      layers <- .read_annotations_at(path, qupath, export_level, call)
      if (qupath) layers <- .split_qupath_layers(layers, e_layers, e_rois)
      got <- unlist(lapply(layers, function(L) vapply(L$rois, `[[`, character(1), "id")))
      if (anyDuplicated(got)) {
        .at_abort("{.file {f[['path']]}} contains duplicate ROI ids.", code = "DUPLICATE_ID", call = call)
      }
      want <- vapply(e_rois, function(r) r[["roi_id"]], character(1))
      if (length(setdiff(want, got)) || length(setdiff(got, want))) {
        .at_abort(
          c("ROI ids in {.file {f[['path']]}} do not match the manifest.",
            "x" = "Missing from the file: {.val {setdiff(want, got)}}.",
            "x" = "Not in the manifest: {.val {setdiff(got, want)}}."),
          code = "ID_JOIN_MISMATCH", call = call
        )
      }
      for (r in e_rois) {
        hit <- unlist(lapply(layers, function(L) Filter(function(x) identical(x$id, r[["roi_id"]]), L$rois)),
                      recursive = FALSE)
        if (length(hit) && !identical(hit[[1]]$label, r[["label"]])) {
          .at_abort("ROI {.val {r[['roi_id']]}} is labelled {.val {hit[[1]]$label}} but the manifest says {.val {r[['label']]}}.",
                    code = "LABEL_MISMATCH", call = call)
        }
      }
      layers <- .tag_imported(layers, v$digest, e_rois, source_ids = src_ids)
      checks <- rbind(checks, .check_row(paste0("annotations:", key), "ok",
                                         sprintf("%d ROIs joined by id at level %d", length(got),
                                                 export_level)))
      cv <- .conversion_rows(layers, e_rois, man[["images"]])
      if (any(cv$geometry_match == "changed", na.rm = TRUE)) {
        checks <- rbind(checks, .check_row(paste0("geometry:", key), "warn",
                                           "some geometries differ from their manifest digests"))
      }
      conv[[length(conv) + 1L]] <- cv
      layers_out[[key]] <- layers
    }
    for (rec in Filter(function(m) !is.null(m[["file"]]) && !is.na(m[["file"]]), man[["masks"]] %||% list())) {
      in_entry <- if (is.na(eid)) !grepl("^entries/", rec[["file"]]) else startsWith(rec[["file"]], paste0("entries/", eid, "/"))
      if (!in_entry) next
      masks_out[[rec[["mask_id"]] %||% rec[["file"]]]] <- .read_mask_file(v$dir, rec, call)
    }
  }
  if (length(masks_out)) {
    checks <- rbind(checks, .check_row("masks", "ok",
                                       sprintf("%d masks: dimensions, integers and legends verified", length(masks_out))))
  }
  flat_layers <- if (length(layers_out) == 1L && identical(names(layers_out), "project")) layers_out$project else layers_out
  list(
    source_name = basename(v$dir),
    handoff_digest = v$digest,
    manifest = man,
    checks = checks,
    objects = list(layers = flat_layers, masks = masks_out, images = man[["images"]]),
    conversion = if (length(conv)) do.call(rbind, conv) else .conversion_rows(list()),
    annotation_revision = if (length(layers_out) == 1L && identical(names(layers_out), "project")) {
      at_annotation_revision(structure(list(layers = layers_out$project), class = "annot_project"))
    } else NA_character_
  )
}

.import_single_geojson <- function(file, qupath, call) {
  src_ids <- .checked_source_ids(file, qupath, call)
  layers <- if (qupath) {
    .split_qupath_layers(at_read_qupath(file, call = call))
  } else {
    at_read_geojson(file, call = call)
  }
  ids <- unlist(lapply(layers, function(L) vapply(L$rois, `[[`, character(1), "id")))
  checks <- .check_row("parse", "ok", sprintf("%d features", length(ids)))
  if (anyDuplicated(ids)) {
    .at_abort("{.file {basename(file)}} contains duplicate ROI ids.", code = "DUPLICATE_ID", call = call)
  }
  n_minted <- sum(!ids %in% src_ids)
  if (n_minted > 0L) {
    checks <- rbind(checks, .check_row(
      "ids", "warn",
      sprintf("%d feature(s) without an id; ids were minted and they stage as new ROIs", n_minted)
    ))
  }
  layers <- .tag_imported(layers, .sha256_file(file), source_ids = src_ids)
  list(
    source_name = basename(file), handoff_digest = NA_character_, manifest = NULL,
    checks = rbind(checks, .check_row("integrity", "warn", "single file: no inventory to verify")),
    objects = list(layers = layers, masks = list(), images = list()),
    conversion = .conversion_rows(layers),
    annotation_revision = at_annotation_revision(structure(list(layers = layers), class = "annot_project"))
  )
}

.import_single_mask <- function(file, npy, call) {
  invalid <- function(e) {
    .at_abort(c("{.file {basename(file)}} is not a valid mask.", "x" = conditionMessage(e)),
              code = "MASK_INVALID", call = call)
  }
  side <- tryCatch(.mask_read_sidecar(file), error = invalid)
  synthesised <- is.null(side[["legend"]]) || length(side[["legend"]]) == 0L
  if (!synthesised) {
    # A sidecar legend must explain every value; check before the mask
    # constructor so the failure carries its own code.
    raw <- if (npy) .npy_read_matrix(file, call = call) else .read_mask_matrix(file, call)$m
    md <- side[["mask_metadata"]]
    missing <- .unexplained_values(raw, as.integer(side[["legend"]][["value"]]),
                                   md[["background"]] %||% 0L, md[["encoding"]] %||% "instance")
    if (length(missing)) {
      .at_abort("Mask values {.val {missing}} are missing from the legend.", code = "LEGEND_INCOMPLETE",
                call = call)
    }
  }
  mk <- tryCatch(
    if (npy) {
      at_read_npy(file, call = call)
    } else {
      rd <- .read_mask_matrix(file, call)
      .mask_recover(rd$m, rd$mask, side)
    },
    error = invalid
  )
  info <- .mask_info(mk)
  m <- info$m
  checks <- .check_row("parse", "ok", sprintf("%d x %d px; %s encoding, background %d", ncol(m), nrow(m),
                                              info$metadata$encoding, info$metadata$background))
  checks <- rbind(checks, if (synthesised) {
    .check_row("legend", "warn", "no legend sidecar: labels are the mask values")
  } else {
    .check_row("legend", "ok", "all values labelled")
  })
  list(
    source_name = basename(file), handoff_digest = NA_character_, manifest = NULL,
    checks = checks,
    objects = list(layers = list(), masks = list(mask = mk), images = list()),
    conversion = .conversion_rows(list()),
    annotation_revision = NA_character_
  )
}

#' @export
print.at_import_report <- function(x, ...) {
  cat(cli::format_inline("{.cls at_import_report} {x$format} {.file {x$source_name}} ({x$status})"), "\n", sep = "")
  n_rois <- nrow(x$conversion)
  cat("  layers: ", length(x$objects$layers), "  |  ROIs: ", n_rois,
      "  |  masks: ", length(x$objects$masks), "\n", sep = "")
  for (i in seq_len(nrow(x$checks))) {
    cat(sprintf("  [%s] %s %s\n", x$checks$status[i], x$checks$check[i], x$checks$detail[i]))
  }
  invisible(x)
}

# ---- Stage and commit ------------------------------------------------------------

.incoming_layers <- function(patch, call) {
  if (inherits(patch, "at_import_report")) {
    L <- patch$objects$layers
    if (length(L) && all(vapply(L, inherits, logical(1), "annot_layer"))) return(L)
    if (length(L) == 1L && is.list(L[[1]])) return(L[[1]])
    .at_abort("The import report holds several entries; stage one entry at a time.",
              code = "PATCH_AMBIGUOUS", call = call)
  }
  if (inherits(patch, "annot_layer")) {
    return(stats::setNames(list(patch), patch$name))
  }
  if (is.list(patch) && length(patch) && all(vapply(patch, inherits, logical(1), "annot_layer"))) {
    return(stats::setNames(patch, vapply(patch, `[[`, character(1), "name")))
  }
  if (.is_string(patch) && file.exists(patch)) {
    return(.incoming_layers(at_import_qupflowr(patch, call = call), call))
  }
  .at_abort("{.arg patch} must be an import report, a handoff path, or annotation layer(s).",
            call = call)
}

.find_roi <- function(project, id) {
  for (nm in names(project$layers)) {
    for (r in project$layers[[nm]]$rois) {
      if (identical(r$id, id)) return(list(roi = r, layer = nm))
    }
  }
  NULL
}

.roi_signature <- function(r, layer) {
  rec <- .roi_record(r, layer)
  .digest_json(rec[c("layer", "label", "level", "geometry_sha256", "locked", "plane")])
}

# Refuse a patch that names one ROI id twice: the second ROI would otherwise
# be silently re-minted and the receipt would name an ROI that does not exist.
.check_incoming_ids <- function(incoming, call) {
  ids <- unlist(lapply(incoming, function(L) vapply(L$rois, function(r) as.character(r$id), character(1))))
  if (anyDuplicated(ids)) {
    .at_abort("The patch contains ROI id{?s} {.val {unique(ids[duplicated(ids)])}} more than once.",
              code = "DUPLICATE_ID", call = call)
  }
  invisible(ids)
}

# An incoming ROI expressed at `level` of the target image, so ROIs exported
# at another pyramid level compare and update consistently. Unchanged when the
# image does not declare both levels.
.roi_at_level <- function(r, level, image) {
  from <- as.integer(r$level)
  to <- as.integer(level)
  if (identical(from, to) || is.null(image) || max(from, to) > image$n_levels - 1L) {
    return(r)
  }
  out <- at_transform(r, from_level = from, to_level = to, img = image)
  out$modified <- r$modified
  out
}

# Same annotation content? Exact signatures, or equal up to floating-point
# noise from a level transform.
.same_roi_content <- function(a, layer_a, b, layer_b) {
  if (identical(.roi_signature(a, layer_a), .roi_signature(b, layer_b))) {
    return(TRUE)
  }
  ra <- .roi_record(a, layer_a)
  rb <- .roi_record(b, layer_b)
  fields <- c("layer", "label", "level", "locked", "plane")
  identical(.digest_json(ra[fields]), .digest_json(rb[fields])) &&
    .geom_equivalent(a$geometry, b$geometry)
}

# Are two geometries the same up to relative noise `tol`?
.geom_equivalent <- function(a, b, tol = 1e-9) {
  if (!identical(as.character(sf::st_geometry_type(a)), as.character(sf::st_geometry_type(b)))) {
    return(FALSE)
  }
  ca <- sf::st_coordinates(a)
  cb <- sf::st_coordinates(b)
  if (!identical(dim(ca), dim(cb))) {
    return(FALSE)
  }
  all(abs(ca - cb) <= tol * max(1, abs(ca[, 1:2])))
}

#' Stage partner changes against a hyperannotatR project
#'
#' Compute, without applying, the changes a partner patch would make to an
#' hyperannotatR project: ROIs are joined by id and classified as `create`,
#' `update`, `unchanged`, `delete` (only with `delete_missing = TRUE`) or
#' `conflict`. Reviewed or locked ROIs, and ROIs in locked layers, are never
#' changed automatically, and nothing is created in or moved into a locked
#' layer; such changes become conflicts. Incoming ROIs whose id was minted on
#' import (features without an id) are always created, with an id unique in
#' the project. Incoming ROIs at another pyramid level are compared, and
#' updates stored, at the level of the existing ROI. A patch that repeats an
#' ROI id aborts (`DUPLICATE_ID`). When `expected_revision` is given and the
#' project has moved on, staging aborts with an `at_conflict_error`
#' (`REVISION_CONFLICT`).
#'
#' @param x An [annot_project], or the path of a saved project `.rds` (then the
#'   commit re-reads and re-checks that file).
#' @param patch An import report from [at_import_qupflowr()], a handoff
#'   directory, or one or more [annot_layer] objects.
#' @param expected_revision Optional revision of `x` the partner based its patch
#'   on (see [at_annotation_revision()]).
#' @param delete_missing Logical; treat ROIs absent from the patch's layers as
#'   deletions. Default `FALSE`.
#' @param call The calling environment, for error reporting.
#'
#' @return An `at_staged_patch`: a list with `patch_id`, `state = "staged"`,
#'   `created`, `base_revision`, `proposed_revision`, `operations` (tibble of
#'   `op`, `roi_id`, `layer`, `label`, `reason`), `summary` (counts by `op`),
#'   `base`, `proposed` (the would-be project), `target_path` and
#'   `patch_digest`.
#' @family interop
#' @seealso [at_commit_qupflowr()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE)
#' proj <- at_example_project()
#' partner <- at_layer_add(at_layer("regions"), at_roi_rect(10, 10, 40, 40, label = "tumour",
#'                                                          id = "partner-1"))
#' st <- at_stage_qupflowr(proj, partner, expected_revision = at_annotation_revision(proj))
#' st$summary
at_stage_qupflowr <- function(x, patch, expected_revision = NULL, delete_missing = FALSE,
                              call = rlang::caller_env()) {
  target_path <- NA_character_
  if (.is_string(x)) {
    .check_file(x, call = call)
    target_path <- normalizePath(x, winslash = "/")
    x <- at_load_project(x, call = call)
  }
  .check_project(x, call = call)
  .check_flag(delete_missing, call = call)
  base_revision <- at_annotation_revision(x)
  if (!is.null(expected_revision) && !identical(expected_revision, base_revision)) {
    .at_abort(
      c("The project changed since the partner read it.",
        "x" = "Expected revision {.val {expected_revision}}, current {.val {base_revision}}.",
        "i" = "Re-read the project state, rebuild the patch and stage again."),
      class = "conflict", code = "REVISION_CONFLICT",
      details = list(expected = expected_revision, actual = base_revision), call = call
    )
  }
  incoming <- .incoming_layers(patch, call)
  incoming_ids <- .check_incoming_ids(incoming, call)
  taken <- c(unlist(lapply(x$layers, function(L) vapply(L$rois, function(r) as.character(r$id), character(1)))),
             incoming_ids)
  proposed <- x
  ops <- list()
  add_op <- function(op, id, layer, label, reason = "") {
    ops[[length(ops) + 1L]] <<- tibble::tibble(op = op, roi_id = id, layer = layer, label = label,
                                                reason = reason)
  }
  protected <- function(r, layer) {
    if (identical(r$attributes[["review_status"]], "reviewed")) return("existing ROI is reviewed")
    if (isTRUE(r$attributes[["locked"]])) return("existing ROI is locked")
    if (isTRUE(x$layers[[layer]]$style$locked)) return("existing layer is locked")
    ""
  }
  seen <- character()
  for (L in incoming) {
    target_locked <- isTRUE(x$layers[[L$name]]$style$locked)
    if (is.null(proposed$layers[[L$name]])) {
      proposed <- at_add_layer(proposed, at_layer(L$name, labels = L$labels, style = L$style))
    }
    for (r in L$rois) {
      if (isTRUE(.jget(r$attributes, "qupflowr", "id_minted"))) {
        # A reader-minted id says nothing about identity: never join it.
        r$id <- .unique_id(taken)
        taken <- c(taken, r$id)
        hit <- NULL
      } else {
        hit <- .find_roi(x, r$id)
      }
      seen <- c(seen, r$id)
      if (is.null(hit)) {
        if (target_locked) {
          add_op("conflict", r$id, L$name, r$label, "target layer is locked")
          next
        }
        proposed <- at_add_roi(proposed, L$name, r)
        add_op("create", r$id, L$name, r$label)
        next
      }
      r <- .roi_at_level(r, hit$roi$level, x$image)
      if (.same_roi_content(hit$roi, hit$layer, r, L$name)) {
        add_op("unchanged", r$id, L$name, r$label)
        next
      }
      why <- protected(hit$roi, hit$layer)
      if (!nzchar(why) && target_locked) why <- "target layer is locked"
      if (nzchar(why)) {
        add_op("conflict", r$id, L$name, r$label, why)
      } else {
        proposed <- suppressWarnings(at_remove_roi(proposed, r$id))
        r$modified <- .now()
        proposed <- at_add_roi(proposed, L$name, r)
        add_op("update", r$id, L$name, r$label)
      }
    }
  }
  if (delete_missing) {
    for (nm in intersect(names(incoming), names(x$layers))) {
      for (r in x$layers[[nm]]$rois) {
        if (r$id %in% seen) next
        why <- protected(r, nm)
        if (nzchar(why)) {
          add_op("conflict", r$id, nm, r$label, paste("delete refused:", why))
        } else {
          proposed <- at_remove_roi(proposed, r$id)
          add_op("delete", r$id, nm, r$label)
        }
      }
    }
  }
  ops_tbl <- if (length(ops)) do.call(rbind, ops) else tibble::tibble(
    op = character(), roi_id = character(), layer = character(), label = character(),
    reason = character()
  )
  summary <- as.list(table(factor(ops_tbl$op, levels = c("create", "update", "unchanged",
                                                         "delete", "conflict"))))
  summary <- lapply(summary, as.integer)
  proposed_revision <- at_annotation_revision(proposed)
  patch_digest <- .digest_json(list(
    base_revision = base_revision, proposed_revision = proposed_revision,
    operations = lapply(seq_len(nrow(ops_tbl)), function(i) as.list(ops_tbl[i, ]))
  ))
  structure(list(
    patch_id = .uuid(),
    state = "staged",
    created = .utc_stamp(),
    base_revision = base_revision,
    expected_revision = expected_revision %||% NA_character_,
    proposed_revision = proposed_revision,
    operations = ops_tbl,
    summary = summary,
    base = x,
    proposed = proposed,
    target_path = target_path,
    source = if (inherits(patch, "at_import_report")) patch$handoff_digest else NA_character_,
    patch_digest = patch_digest
  ), class = "at_staged_patch")
}

#' @export
print.at_staged_patch <- function(x, ...) {
  s <- x$summary
  cat(cli::format_inline("{.cls at_staged_patch} {x$patch_id} ({x$state})"), "\n", sep = "")
  cat(sprintf("  create %d | update %d | unchanged %d | delete %d | conflict %d\n",
              s$create, s$update, s$unchanged, s$delete, s$conflict))
  cat("  base ", x$base_revision, "\n  proposed ", x$proposed_revision, "\n", sep = "")
  invisible(x)
}

.commit_registry <- new.env(parent = emptyenv())

#' Commit a staged partner patch
#'
#' Apply an [at_stage_qupflowr()] patch. Conflicting operations are never
#' applied. The commit is idempotent: repeating it with the same
#' `idempotency_key` and the same patch returns the original receipt without
#' applying anything again, while the same key with a different patch aborts
#' with `IDEMPOTENCY_CONFLICT`. When the patch targets a saved project file (or
#' `destination` names one), the file is re-read and its revision re-checked
#' immediately before writing; an existing file is only replaced with
#' `overwrite = TRUE`. A `<file>.commit.json` receipt records the key across R
#' sessions.
#'
#' @param x An `at_staged_patch`.
#' @param idempotency_key Optional client key; defaults to one derived from the
#'   patch id.
#' @param destination Optional project `.rds` path to write the committed
#'   project to; defaults to the patch's `target_path` when staged from a file.
#' @param overwrite Logical; allow replacing an existing project file.
#' @param call The calling environment, for error reporting.
#'
#' @return An `at_commit_receipt`: a list with `state = "committed"`,
#'   `patch_id`, `idempotency_key`, `previous_revision`, `new_revision`,
#'   `applied` and `conflicts` (operation tibbles), `project`, `written` (path or
#'   `NA`), `committed_at` and `replayed`.
#' @family interop
#' @seealso [at_stage_qupflowr()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE)
#' proj <- at_example_project()
#' partner <- at_layer_add(at_layer("regions"), at_roi_rect(10, 10, 40, 40, label = "tumour",
#'                                                          id = "partner-1"))
#' rc <- at_commit_qupflowr(at_stage_qupflowr(proj, partner))
#' rc$new_revision
at_commit_qupflowr <- function(x, idempotency_key = NULL, destination = NULL, overwrite = FALSE,
                               call = rlang::caller_env()) {
  .check_class(x, "at_staged_patch", call = call)
  .check_flag(overwrite, call = call)
  key <- idempotency_key %||% paste0("patch-", x$patch_id)
  .check_string(key, call = call)
  if (!grepl("^[A-Za-z0-9._:-]{1,128}$", key)) {
    .at_abort("{.arg idempotency_key} must be 1-128 characters of letters, digits, '.', '_', ':' or '-'.",
              call = call)
  }
  prior <- .commit_registry[[key]]
  if (!is.null(prior)) {
    if (!identical(prior$patch_digest, x$patch_digest)) {
      .at_abort("The idempotency key {.val {key}} was already used for a different patch.",
                class = "conflict", code = "IDEMPOTENCY_CONFLICT", call = call)
    }
    out <- prior$receipt
    out$replayed <- TRUE
    return(out)
  }
  target <- destination %||% (if (is.na(x$target_path)) NULL else x$target_path)
  if (!is.null(target)) {
    .check_string(target, call = call)
    side <- paste0(target, ".commit.json")
    if (file.exists(side)) {
      rec <- tryCatch(.read_json_doc(side, call = call), error = function(e) NULL)
      if (identical(rec[["idempotency_key"]], key)) {
        if (!identical(rec[["patch_digest"]], x$patch_digest)) {
          .at_abort("The idempotency key {.val {key}} was already used for a different patch.",
                    class = "conflict", code = "IDEMPOTENCY_CONFLICT", call = call)
        }
        proj <- at_load_project(target, call = call)
        return(structure(list(
          state = "committed", patch_id = rec[["patch_id"]], idempotency_key = key,
          previous_revision = rec[["previous_revision"]], new_revision = rec[["new_revision"]],
          applied = x$operations[x$operations$op %in% c("create", "update", "delete"), ],
          conflicts = x$operations[x$operations$op == "conflict", ],
          project = proj, written = normalizePath(target, winslash = "/"),
          committed_at = rec[["committed_at"]], replayed = TRUE
        ), class = "at_commit_receipt"))
      }
    }
    if (file.exists(target)) {
      if (!overwrite) {
        .at_abort(c("{.path {target}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to replace it after the revision check."),
                  class = "io", code = "DESTINATION_EXISTS", call = call)
      }
      current <- at_annotation_revision(at_load_project(target, call = call))
      if (!identical(current, x$base_revision)) {
        .at_abort(
          c("{.path {basename(target)}} changed after the patch was staged.",
            "x" = "Staged against {.val {x$base_revision}}, file now at {.val {current}}."),
          class = "conflict", code = "REVISION_CONFLICT",
          details = list(expected = x$base_revision, actual = current), call = call
        )
      }
    }
  }
  project <- .log_edit(x$proposed, "commit_qupflowr", x$patch_id)
  written <- NA_character_
  committed_at <- .utc_stamp()
  new_rev <- at_annotation_revision(project)
  if (!is.null(target)) {
    # The target is the user's own project file: keep its image source (and
    # reader) so the image can be reopened; drop the pixels and read identity.
    lite <- project
    lite$image$handle <- NULL
    lite$image$read_key <- NULL
    tmp <- tempfile(pattern = ".hyperannotatR-commit-", tmpdir = dirname(target), fileext = ".rds")
    at_save_project(lite, tmp, call = call)
    if (!.rename_path(tmp, target)) {
      unlink(tmp)
      .at_abort("Could not replace {.path {basename(target)}}.", class = "io",
                code = "WRITE_FAILED", call = call)
    }
    written <- normalizePath(target, winslash = "/")
    .write_json_atomic(list(
      document = "annotatr_commit_receipt", idempotency_key = key, patch_id = x$patch_id,
      patch_digest = x$patch_digest, previous_revision = x$base_revision,
      new_revision = new_rev, committed_at = committed_at
    ), paste0(target, ".commit.json"))
  }
  receipt <- structure(list(
    state = "committed",
    patch_id = x$patch_id,
    idempotency_key = key,
    previous_revision = x$base_revision,
    new_revision = new_rev,
    applied = x$operations[x$operations$op %in% c("create", "update", "delete"), ],
    conflicts = x$operations[x$operations$op == "conflict", ],
    project = project,
    written = written,
    committed_at = committed_at,
    replayed = FALSE
  ), class = "at_commit_receipt")
  assign(key, list(patch_digest = x$patch_digest, receipt = receipt), envir = .commit_registry)
  receipt
}

#' @export
print.at_commit_receipt <- function(x, ...) {
  cat(cli::format_inline("{.cls at_commit_receipt} {x$patch_id} ({x$state}{if (isTRUE(x$replayed)) ', replayed' else ''})"),
      "\n", sep = "")
  cat("  applied ", nrow(x$applied), " | conflicts ", nrow(x$conflicts), "\n", sep = "")
  cat("  ", x$previous_revision, " -> ", x$new_revision, "\n", sep = "")
  invisible(x)
}
