# QuPath GeoJSON dialect.
#
# QuPath 0.4+ (verified against a real QuPath 0.7.0 export, see
# tests/testthat/fixtures/qupath-0.7.0) writes `properties.objectType`,
# `classification = {name | names, color = [r, g, b]}`, `isLocked` only when
# locked, the object UUID as the feature `id`, a non-default image plane as
# `geometry.plane`, ellipses as polygons flagged `geometry.isEllipse`, cell
# nuclei as a feature-level `nucleusGeometry`, and `measurements` as a flat
# object whose non-finite values are strings such as "NaN". QuPath silently
# replaces feature ids that are not UUIDs, so the QuPath dialect writes a
# deterministic UUID per ROI and keeps hyperannotatR's own id in
# `properties.metadata`.
#
# The legacy hyperannotatR 0.1 dialect (`object_type`, signed 32-bit `colorRGB`) is
# still readable and can still be written with `dialect = "legacy"`. QuPath's
# colorRGB packs 0xFFRRGGBB into a signed int, so the hex <-> int conversion
# uses modular arithmetic to avoid integer overflow.

# Hex colour -> QuPath signed 32-bit colorRGB.
.hex_to_signed_int <- function(hex) {
  c3 <- grDevices::col2rgb(hex)
  unsigned <- 255 * 16777216 + c3[1] * 65536 + c3[2] * 256 + c3[3]
  as.integer(if (unsigned >= 2147483648) unsigned - 4294967296 else unsigned)
}

# QuPath signed 32-bit colorRGB -> hex colour. Writers that store the packed
# value unsigned (0xFFRRGGBB >= 2^31) are accepted too.
.signed_int_to_hex <- function(val) {
  val <- as.numeric(val)
  unsigned <- if (val < 0) val + 4294967296 else val
  b <- unsigned %% 256
  g <- (unsigned %/% 256) %% 256
  r <- (unsigned %/% 65536) %% 256
  grDevices::rgb(r, g, b, maxColorValue = 255)
}

.uuid_pattern <- "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

# Deterministic UUID (version 8, RFC 9562 "custom") derived from a hyperannotatR
# ROI id, so repeated exports of the same ROI give QuPath the same object id.
# The hash seed keeps its pre-rename spelling so that ids stay those of
# annotatR exports. An id that already is a UUID is kept unchanged.
.roi_uuid <- function(id) {
  if (grepl(.uuid_pattern, id)) {
    return(tolower(id))
  }
  h <- substr(.sha256_bytes(paste0("annotatR:roi:", id)), 1L, 32L)
  chars <- strsplit(h, "")[[1]]
  chars[13] <- "8"
  chars[17] <- c("8", "9", "a", "b")[(strtoi(chars[17], 16L) %% 4L) + 1L]
  h <- paste(chars, collapse = "")
  paste(substr(h, 1, 8), substr(h, 9, 12), substr(h, 13, 16), substr(h, 17, 20),
        substr(h, 21, 32), sep = "-")
}

# `g` holds the coordinates written and `level` the pyramid level they refer
# to. Both dialects carry `level`, `source_level` (the ROI's stored level) and
# `coordinate_schema` properties. QuPath keeps only `metadata` through its own
# import and export, so the QuPath dialect repeats the coordinate declaration
# there as strings (`annotatr_coordinate_schema`, `annotatr_coordinate_level`);
# `annotatr_level` keeps its hyperannotatR 0.2.0 meaning, the ROI's stored level.
.roi_to_qupath_feature <- function(r, layer_name, g, colour, dialect = "qupath",
                                   level = r$level) {
  object_type <- r$attributes$qupath$object_type %||%
    (if (r$source %in% c("mask", "derived")) "detection" else "annotation")
  levels <- list(level = as.integer(level), source_level = as.integer(r$level),
                 coordinate_schema = .coordinate_schema)
  if (identical(dialect, "legacy")) {
    return(list(
      type = "Feature",
      id = r$id,
      geometry = .sfg_to_geojson(g),
      properties = c(list(
        object_type = object_type,
        classification = list(name = r$label, colorRGB = .hex_to_signed_int(colour)),
        isLocked = isTRUE(r$attributes$locked),
        layer = layer_name
      ), levels)
    ))
  }
  geometry <- .sfg_to_geojson(g)
  plane <- r$attributes$plane
  if (is.list(plane) && (isTRUE(plane$z > 0) || isTRUE(plane$t > 0) ||
                         (!is.null(plane$c) && !is.na(plane$c) && plane$c >= 0))) {
    geometry$plane <- list(c = if (is.null(plane$c) || is.na(plane$c)) -1L else as.integer(plane$c),
                           z = as.integer(plane$z %||% 0L), t = as.integer(plane$t %||% 0L))
  }
  rgb <- as.integer(grDevices::col2rgb(colour)[, 1])
  classification <- if (grepl(": ", r$label, fixed = TRUE)) {
    list(names = as.list(strsplit(r$label, ": ", fixed = TRUE)[[1]]), color = as.list(rgb))
  } else {
    list(name = r$label, color = as.list(rgb))
  }
  props <- list(objectType = object_type)
  if (.is_string(r$attributes$qupath$name)) {
    props$name <- r$attributes$qupath$name
  }
  if (!identical(r$label, "unclassified")) {
    props$classification <- classification
  }
  if (isTRUE(r$attributes$locked)) {
    props$isLocked <- TRUE
  }
  props$metadata <- list(
    annotatr_roi_id = r$id,
    annotatr_layer = layer_name,
    annotatr_source = r$source,
    annotatr_level = as.character(as.integer(r$level)),
    annotatr_coordinate_schema = .coordinate_schema,
    annotatr_coordinate_level = as.character(as.integer(level))
  )
  props <- c(props, levels)
  feat <- list(type = "Feature", id = .roi_uuid(r$id), geometry = geometry, properties = props)
  if (!is.null(r$attributes$qupath$nucleus_geometry)) {
    feat$nucleusGeometry <- r$attributes$qupath$nucleus_geometry
  }
  feat
}

#' Write a project's ROIs as QuPath GeoJSON
#'
#' The default `dialect = "qupath"` writes what QuPath 0.4 and later read
#' natively (verified with QuPath 0.7.0): `objectType`, `classification` with
#' an `[r, g, b]` colour, `isLocked` for locked ROIs, a deterministic UUID per
#' ROI as the feature id (QuPath replaces non-UUID ids; existing UUIDs are
#' kept), and hyperannotatR's own ROI id, layer, source and stored level in
#' `properties.metadata`. `dialect = "legacy"` writes the hyperannotatR 0.1 form
#' (`object_type`, signed `colorRGB`), which QuPath still reads with a
#' deprecation warning. Publication uses a staged replacement.
#'
#' Every feature records the pyramid level of its written coordinates as the
#' `level` property, the ROI's stored level as `source_level`, and the marker
#' `coordinate_schema = "annotatR-pixel-level-v1"`. QuPath keeps only
#' `metadata` through its own import and export, so the QuPath dialect repeats
#' the declaration there as `annotatr_coordinate_schema` and
#' `annotatr_coordinate_level`; [at_read_qupath()] restores ROIs at that level.
#'
#' QuPath keeps one colour per classification name, so a label that has
#' different colours in different layers is written with the first colour
#' found for it.
#'
#' @param project An [annot_project].
#' @param path Output file path.
#' @param layer Optional layer filter.
#' @param level Integer pyramid level for the coordinates and the `level`
#'   property. Default `0`, as QuPath expects; other levels are for consumers
#'   that explicitly support them.
#' @param overwrite Logical; overwrite an existing file. Default `FALSE`.
#' @param dialect `"qupath"` (default) or `"legacy"`.
#' @param call The calling environment, for error reporting.
#'
#' @return The output path, invisibly.
#' @family io
#' @seealso [at_read_qupath()], [at_write_geojson()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE)
#' p <- tempfile(fileext = ".geojson")
#' at_write_qupath(at_example_project(), p)
at_write_qupath <- function(project, path, layer = NULL, level = 0L,
                            overwrite = FALSE, dialect = c("qupath", "legacy"),
                            call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(path, call = call)
  .check_flag(overwrite, call = call)
  dialect <- .check_choice(dialect, c("qupath", "legacy"), call = call)
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(c("{.path {path}} already exists.",
                    "i" = "Pass {.code overwrite = TRUE} to replace it."), call = call)
  }
  height <- at_dims(project$image, level)[2]
  fc <- .project_to_features(project, layer, level, flip_y = FALSE, height = height,
                             qupath = TRUE, dialect = dialect)
  fc$features <- .qupath_unify_colours(fc$features)
  ids <- vapply(fc[["features"]], function(f) as.character(f[["id"]]), character(1))
  if (anyDuplicated(tolower(ids))) {
    .at_abort("Conflicting QuPath output UUIDs: {.val {unique(ids[duplicated(tolower(ids))])}}.",
              code = "DUPLICATE_ID", call = call)
  }
  .export_bundle(path, function(stage) {
    jsonlite::write_json(fc, stage[1], auto_unbox = TRUE, digits = I(17), null = "null",
                         pretty = TRUE)
  }, overwrite)
  invisible(path)
}

# Give every feature of one label the colour of its first feature, as QuPath
# keeps one colour per classification name.
.qupath_unify_colours <- function(features) {
  seen <- list()
  for (i in seq_along(features)) {
    cls <- features[[i]][["properties"]][["classification"]]
    if (is.null(cls)) next
    label <- .qupath_label(cls)
    field <- if (!is.null(cls[["color"]])) "color" else "colorRGB"
    if (is.null(seen[[label]])) {
      seen[[label]] <- cls[[field]]
    } else {
      features[[i]][["properties"]][["classification"]][[field]] <- seen[[label]]
    }
  }
  features
}

# ---- Reading -------------------------------------------------------------------

.qupath_malformed <- function(what, call = rlang::caller_env()) {
  .at_abort("Malformed QuPath {what}.", code = "INVALID_GEOJSON", call = call)
}

.qupath_string <- function(x, field, call = rlang::caller_env()) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    .at_abort("Malformed QuPath {field}; expected one nonempty string.",
              code = "INVALID_GEOJSON", call = call)
  }
  invisible(x)
}

# The value all non-NULL declarations agree on (NULL when none is given);
# contradictory declarations are refused rather than one of them selected.
# Numbers compare exactly.
.qupath_consistent <- function(values, field, call = rlang::caller_env()) {
  values <- Filter(Negate(is.null), values)
  if (!length(values)) {
    return(NULL)
  }
  reference <- values[[1]]
  equal <- function(x) {
    if (is.numeric(x) && is.numeric(reference)) {
      identical(as.numeric(x), as.numeric(reference))
    } else {
      identical(x, reference)
    }
  }
  if (!all(vapply(values, equal, logical(1)))) {
    .at_abort("Conflicting QuPath {field} declarations.", code = "INVALID_GEOJSON", call = call)
  }
  reference
}

# jsonlite keeps duplicate object names. QuPath 0.7.0 repeats identical
# metadata objects, which are accepted; contradictory duplicates are refused
# instead of silently taking the first.
.qupath_object <- function(x, call = rlang::caller_env()) {
  if (!is.list(x)) {
    return(x)
  }
  x[] <- lapply(x, .qupath_object, call = call)
  if (!is.null(names(x))) {
    for (nm in unique(names(x))) {
      copies <- x[names(x) == nm]
      if (!all(vapply(copies, identical, logical(1), copies[[1]]))) {
        .at_abort("Conflicting QuPath duplicate field {.field {nm}}.", code = "INVALID_GEOJSON",
                  call = call)
      }
    }
    x <- x[!duplicated(names(x))]
  }
  x
}

# Features of a parsed GeoJSON document: a FeatureCollection, a bare array of
# features (QuPath's native export) or a single Feature. Keys are matched
# exactly, so e.g. `features_extra` never stands in for `features`. The
# features themselves are validated by the reader.
.qupath_features <- function(doc, call = rlang::caller_env()) {
  if (!is.list(doc)) {
    .qupath_malformed("GeoJSON root", call = call)
  }
  if (identical(doc[["type"]], "FeatureCollection")) {
    feats <- doc[["features"]]
    if (!is.list(feats) || !is.null(names(feats))) {
      .qupath_malformed("FeatureCollection features", call = call)
    }
    return(feats)
  }
  if (identical(doc[["type"]], "Feature")) {
    return(list(doc))
  }
  if (is.null(names(doc))) {
    return(doc)
  }
  .qupath_malformed("GeoJSON root", call = call)
}

# Label from a QuPath classification (single or derived name list).
.qupath_label <- function(cls, call = rlang::caller_env()) {
  if (is.null(cls)) {
    return("unclassified")
  }
  if (!is.null(cls[["name"]])) {
    .qupath_string(cls[["name"]], "classification name", call = call)
    return(cls[["name"]])
  }
  parts <- cls[["names"]]
  if (!is.null(parts) && length(parts) > 0L) {
    for (p in parts) .qupath_string(p, "classification names", call = call)
    return(paste(unlist(parts), collapse = ": "))
  }
  "unclassified"
}

# Colour of a classification: the current `color` RGB array or the legacy
# signed (or unsigned) packed `colorRGB`; both must agree when present.
.qupath_colour <- function(cls, call = rlang::caller_env()) {
  if (is.null(cls)) {
    return(NULL)
  }
  current <- legacy <- NULL
  if (!is.null(cls[["color"]])) {
    rgb <- cls[["color"]]
    ok <- is.list(rgb) && is.null(names(rgb)) && length(rgb) == 3L &&
      all(vapply(rgb, function(v) {
        is.numeric(v) && length(v) == 1L && is.finite(v) && v == floor(v) && v >= 0 && v <= 255
      }, logical(1)))
    if (!ok) .qupath_malformed("classification color RGB array", call = call)
    rgb <- unlist(rgb)
    current <- grDevices::rgb(rgb[1], rgb[2], rgb[3], maxColorValue = 255)
  }
  if (!is.null(cls[["colorRGB"]])) {
    v <- cls[["colorRGB"]]
    if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v != floor(v) ||
        v < -2147483648 || v > 4294967295) {
      .qupath_malformed("classification colorRGB", call = call)
    }
    legacy <- .signed_int_to_hex(v)
  }
  .qupath_consistent(list(current, legacy), "classification colour", call = call)
}

# Validate the nesting and numbers of a GeoJSON geometry before conversion.
.qupath_geometry <- function(g, call = rlang::caller_env()) {
  type <- g[["type"]]
  if (!is.character(type) || length(type) != 1L) {
    .qupath_malformed("GeoJSON geometry type", call = call)
  }
  depth <- switch(type, Point = 0L, MultiPoint = 1L, LineString = 1L, Polygon = 2L,
                  MultiPolygon = 3L,
                  .at_abort("Unsupported QuPath GeoJSON geometry type {.val {type}}.",
                            code = "INVALID_GEOJSON", call = call))
  coords <- function(x, n) {
    if (!is.list(x) || !is.null(names(x)) || !length(x)) {
      .qupath_malformed("GeoJSON coordinates", call = call)
    }
    if (n == 0L) {
      finite <- function(v) is.numeric(v) && length(v) == 1L && is.finite(v)
      if (length(x) != 2L || !all(vapply(x, finite, logical(1)))) {
        .qupath_malformed("GeoJSON coordinate pair", call = call)
      }
    } else {
      for (part in x) coords(part, n - 1L)
    }
  }
  coords(g[["coordinates"]], depth)
}

# QuPath measurements -> tibble with explicit value states. QuPath writes
# non-finite values as strings ("NaN", "Infinity", "-Infinity"). QuPath before
# 0.4 wrote an array of {name, value} objects instead of a flat object.
.qupath_measurements <- function(ms) {
  if (is.null(ms) || length(ms) == 0L) {
    return(NULL)
  }
  if (is.null(names(ms)) && all(vapply(ms, function(m) is.list(m) && !is.null(m[["name"]]), logical(1)))) {
    nm <- vapply(ms, function(m) as.character(m[["name"]]), character(1))
    ms <- stats::setNames(lapply(ms, function(m) m[["value"]]), nm)
  }
  vals <- lapply(ms, function(v) if (is.null(v)) NA else v)
  state <- vapply(vals, function(v) {
    if (is.character(v)) {
      switch(v, "NaN" = "nan", "Infinity" = "pos_inf", "-Infinity" = "neg_inf", "text")
    } else if (is.numeric(v) && length(v) == 1L && !is.na(v)) {
      "finite"
    } else {
      "missing"
    }
  }, character(1))
  value <- vapply(seq_along(vals), function(i) {
    switch(state[i], finite = as.numeric(vals[[i]]), nan = NaN, pos_inf = Inf,
           neg_inf = -Inf, NA_real_)
  }, numeric(1))
  tibble::tibble(name = names(ms), value = value, value_state = unname(state))
}

# Exact metadata keys that map a QuPath object back to hyperannotatR. Both the
# current lowercase spelling and the annotatR-prefixed spelling of the 2026-09
# roadmap builds (seen in native QuPath 0.7.0 round trips) are accepted;
# when both are present they must agree.
.qupath_mapping_keys <- list(
  roi_id = c("annotatr_roi_id", "annotatR_roi_id"),
  coordinate_schema = c("annotatr_coordinate_schema", "annotatR_coordinate_schema"),
  coordinate_level = c("annotatr_coordinate_level", "annotatR_coordinate_level")
)

#' Read ROIs from a QuPath GeoJSON file
#'
#' Reads QuPath 0.4+ exports (a native feature array, a FeatureCollection or a
#' single Feature) and the legacy hyperannotatR 0.1 dialect.
#' `classification.name` (or the joined `names` of a derived class, e.g.
#' `"Tumor: Positive"`) becomes the ROI label, the classification colour (a
#' current `color` RGB array or a legacy `colorRGB` integer) the layer style
#' colour, and features without a classification are labelled
#' `"unclassified"`. Everything else QuPath carries is kept, never invented,
#' under each ROI's `attributes$qupath`: the object id and type, name,
#' measurements (with explicit `value_state`), the image plane (zero-based
#' `c`, `z`, `t`; `c = NA` for all channels), metadata, a nucleus geometry, and
#' `roi_native = "ellipse"` with `geometry_fidelity = "approximated"` for
#' polygonised ellipses. A hyperannotatR id stored in `metadata.annotatr_roi_id`
#' is restored as the ROI id; ordinary external ids are kept unchanged.
#'
#' Input is validated strictly and keys are matched exactly: malformed
#' structure, contradictory duplicate fields (identical duplicates, which
#' QuPath 0.7.0 emits, are accepted), conflicting colours or object types for
#' a feature, conflicting colours for one label, and repeated ROI ids are
#' refused with an `at_validation_error` of code `INVALID_GEOJSON`.
#'
#' @param path Path to a QuPath GeoJSON file.
#' @param layer_name Layer name for the imported ROIs. Default `"qupath"`.
#' @param level Integer fallback level for features without level metadata.
#'   Default `0` (standard full-resolution QuPath coordinates).
#' @param call The calling environment, for error reporting.
#' @param coordinate_level Optional integer overriding every recorded `level`
#'   without scaling coordinates. Use only when the actual coordinate level is
#'   known, for example `0L` for legacy hyperannotatR exports that wrote level-0
#'   coordinates beside a nonzero source level. `NULL` (default) uses the
#'   schema and `legacy_levels` policy. Coordinates are never automatically
#'   repaired.
#' @param legacy_levels How to interpret files without the coordinate schema
#'   marker: `"error"` (default) rejects ambiguous nonzero recorded levels;
#'   `"recorded"` explicitly trusts those levels. Level-0 files remain
#'   unambiguous.
#'
#' @return An [annot_layer].
#' @family io
#' @export
at_read_qupath <- function(path, layer_name = "qupath", level = 0L,
                           call = rlang::caller_env(), coordinate_level = NULL,
                           legacy_levels = c("error", "recorded")) {
  legacy_levels <- .check_choice(legacy_levels, c("error", "recorded"),
                                 default = missing(legacy_levels), call = call)
  if (!is.null(coordinate_level)) coordinate_level <- .check_count(coordinate_level, call = call)
  level <- .check_count(level, call = call)
  .check_file(path, call = call)
  doc <- tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(e) {
      .at_abort("{.path {basename(path)}} is not valid JSON.", code = "INVALID_JSON", call = call)
    }
  )
  features <- .qupath_features(.qupath_object(doc, call = call), call = call)
  lyr <- at_layer(layer_name)
  colour_map <- character()
  ids <- character()
  for (ft in features) {
    if (!is.list(ft) || !identical(ft[["type"]], "Feature") || !is.list(ft[["geometry"]])) {
      .qupath_malformed("GeoJSON Feature", call = call)
    }
    props <- ft[["properties"]] %||% list()
    if (!is.list(props) || (length(props) && is.null(names(props)))) {
      .qupath_malformed("properties", call = call)
    }
    cls <- props[["classification"]]
    if (!is.null(cls) && (!is.list(cls) || is.null(names(cls)))) {
      .qupath_malformed("classification", call = call)
    }
    label <- .qupath_label(cls, call = call)
    col <- .qupath_colour(cls, call = call)
    if (!is.null(col)) {
      if (label %in% names(colour_map) && !identical(colour_map[[label]], col)) {
        .at_abort("Conflicting QuPath classification colours for label {.val {label}}.",
                  code = "INVALID_GEOJSON", call = call)
      }
      colour_map[[label]] <- col
    }
    kind <- .qupath_consistent(list(props[["objectType"]], props[["object_type"]]),
                               "object type", call = call) %||% "annotation"
    .qupath_string(kind, "object type", call = call)
    meta <- props[["metadata"]] %||% list()
    if (!is.list(meta) || (length(meta) && is.null(names(meta)))) {
      .qupath_malformed("metadata mapping", call = call)
    }
    for (key in intersect(names(meta), unlist(.qupath_mapping_keys))) {
      .qupath_string(meta[[key]], paste("metadata mapping", key), call = call)
    }
    mapped <- function(field) {
      .qupath_consistent(unname(lapply(.qupath_mapping_keys[[field]], function(k) meta[[k]])),
                         gsub("_", " ", field), call = call)
    }
    schema <- .qupath_consistent(list(props[["coordinate_schema"]], mapped("coordinate_schema")),
                                 "coordinate schema", call = call)
    if (!is.null(schema)) .qupath_string(schema, "coordinate schema", call = call)
    recorded <- props[["level"]]
    meta_level <- mapped("coordinate_level")
    if (!is.null(meta_level)) {
      if (!grepl("^[0-9]+$", meta_level)) {
        .qupath_malformed("coordinate metadata mapping", call = call)
      }
      recorded <- .qupath_consistent(list(recorded, as.numeric(meta_level)), "coordinate level",
                                     call = call)
    }
    if (!is.null(ft[["id"]])) .qupath_string(ft[["id"]], "feature ID", call = call)
    rid <- mapped("roi_id") %||% ft[["id"]] %||% .new_id("roi")
    if (rid %in% ids) {
      .at_abort("Duplicate QuPath ROI ID mapping: {.val {rid}}.", code = "INVALID_GEOJSON",
                call = call)
    }
    ids <- c(ids, rid)
    locked <- props[["isLocked"]]
    if (!is.null(locked) && (!is.logical(locked) || length(locked) != 1L || is.na(locked))) {
      .qupath_malformed("isLocked field", call = call)
    }
    geom <- ft[["geometry"]]
    .qupath_geometry(geom, call = call)
    g <- .geojson_to_sfg(geom)
    roi <- at_roi_from_sf(
      sf::st_sfc(g, crs = sf::NA_crs_), label = label,
      level = .import_coordinate_level(recorded, level, schema, coordinate_level,
                                       legacy_levels, call),
      id = rid, source = "imported"
    )
    qp <- list(
      object_id = if (is.null(ft[["id"]])) NA_character_ else ft[["id"]],
      object_type = kind,
      dialect = if (!is.null(props[["objectType"]])) "qupath" else "legacy"
    )
    if (!is.null(props[["name"]])) qp$name <- as.character(props[["name"]])
    if (isTRUE(geom[["isEllipse"]])) {
      qp$roi_native <- "ellipse"
      qp$geometry_fidelity <- "approximated"
    }
    if (!is.null(ft[["nucleusGeometry"]])) qp$nucleus_geometry <- ft[["nucleusGeometry"]]
    if (!is.null(props[["measurements"]])) qp$measurements <- .qupath_measurements(props[["measurements"]])
    if (length(meta)) qp$metadata <- meta
    roi$attributes$qupath <- qp
    plane <- geom[["plane"]]
    if (!is.null(plane)) {
      pc <- plane[["c"]] %||% -1L
      roi$attributes$plane <- list(
        c = if (is.null(pc) || pc < 0) NA_integer_ else as.integer(pc),
        z = as.integer(plane[["z"]] %||% 0L), t = as.integer(plane[["t"]] %||% 0L)
      )
    }
    if (isTRUE(locked)) roi$attributes$locked <- TRUE
    lyr <- at_layer_add(lyr, roi)
  }
  # Apply recovered colours to the layer style.
  if (length(colour_map) > 0L) {
    lyr$style$colour <- .resolve_palette(lyr$labels, colour_map)
  }
  lyr
}
