# The atcanvas htmlwidget: an annotation canvas with pan/zoom and ROI drawing.
#
# The JavaScript (inst/htmlwidgets/atcanvas.js) is a self-contained HTML5 canvas
# with no external libraries, so the widget works fully offline. It displays one
# embedded, downsampled base image per render (a PNG data URI built here); it
# does not stream pyramid tiles. Band and view changes therefore re-render the
# widget from R with a new `view`.
#
# COORDINATE DISCIPLINE: all coordinates that cross the JS -> R boundary are
# level-0 image pixels. The JS converts from canvas/screen coordinates to
# level-0 image pixels before emitting any event; the conversion is the single
# function `toImageCoords()` in atcanvas.js.
#
# EVENT PROTOCOL: browser inputs are {entry_id, revision, payload}, stamped with
# the identity a render or annotation update carried (see .canvas_identity()
# and the "Shiny inputs" section of ?at_canvas). The app rejects stale stamps.

.canvas_tool_names <- c("pan", "rect", "polygon", "freehand", "circle", "point", "edit",
                        "erase", "probe", "select")

.canvas_deps_ok <- function(call = rlang::caller_env()) {
  missing <- character()
  for (p in c("htmlwidgets", "htmltools")) {
    if (!requireNamespace(p, quietly = TRUE)) missing <- c(missing, p)
  }
  if (length(missing) > 0L) {
    cli::cli_abort(
      c("The annotation canvas requires packages not installed.",
        "x" = "Missing: {.pkg {missing}}.",
        "i" = "Install with {.code install.packages(c({paste0('\"', missing, '\"', collapse = ', ')}))}."),
      call = call
    )
  }
  invisible(TRUE)
}

# Natural-colour RGB band triple: nearest bands to ~640/550/460 nm when the
# image has a visible-range spectral axis, else the first three bands. Turns a
# hyperspectral cube into a recognisable photo to annotate on -- pixel-aligned
# to the cube grid, so ROIs and spectra map exactly.
.default_rgb_bands <- function(img, nb) {
  if (nb < 3L) return(rep(1L, 3L))
  wl <- img$wavelengths
  if (!is.null(wl) && length(wl) == nb && min(wl, na.rm = TRUE) <= 700) {
    nearest <- function(target) which.min(abs(wl - target))
    return(c(nearest(640), nearest(550), nearest(460)))
  }
  1:3
}

# Read only the requested bands of the display level, decimated so the longest
# side is at most `max_dim`. Non-pyramidal images are read in row chunks, so a
# preview never materialises the full cube (all bands at full resolution).
.preview_bands <- function(img, bands, max_dim = 2048L) {
  level <- .display_level(img, max_dim)
  d <- at_dims(img, level)
  stride <- max(1L, as.integer(ceiling(max(d) / max_dim)))
  ys <- seq(1L, d[2], by = stride)
  xs <- seq(1L, d[1], by = stride)
  out <- array(NA_real_, dim = c(length(ys), length(xs), length(bands)))
  chunk <- max(stride, as.integer(floor(64e6 / (8 * d[1] * length(bands)))))
  chunk <- chunk - (chunk %% stride)
  row0 <- 1L
  filled <- 0L
  while (row0 <= d[2]) {
    row1 <- min(d[2], row0 + chunk - 1L)
    tile <- at_tile(img, level = level, xrange = c(1L, d[1]), yrange = c(row0, row1),
                    bands = bands)
    keep <- which(((row0:row1) - 1L) %% stride == 0L)
    if (length(keep)) {
      out[filled + seq_along(keep), , ] <- tile[keep, xs, , drop = FALSE]
      filled <- filled + length(keep)
    }
    row0 <- row1 + 1L
  }
  out
}

# Per-channel 2-98% contrast stretch to [0, 1] (display only). A flat min-max
# leaves cube channels dark and washed out; the percentile stretch yields a
# natural-looking photo.
.stretch01 <- function(m) {
  q <- stats::quantile(m, c(0.02, 0.98), na.rm = TRUE)
  if (!all(is.finite(q)) || diff(q) == 0) return(matrix(0, nrow(m), ncol(m)))
  out <- pmin(pmax((m - q[1]) / diff(q), 0), 1)
  out[is.na(out)] <- 0
  out
}

# Render a display array for a band view: "rgb" and "single" use raw bands,
# registered operations are computed on the decimated bands. `NULL` is the
# default natural-colour view (the first band for fewer than three bands).
.view_display_array <- function(img, view = NULL, max_dim = 2048L) {
  nb <- img$n_bands
  # The default view of an 8-bit image keeps its stored values (see
  # .display_native()); chosen views and deeper data are stretched.
  natural <- is.null(view)
  view <- view %||% if (nb < 3L) list(operation = "single", bands = 1L) else list(operation = "rgb")
  spec <- .check_band_view(img, view$operation %||% "rgb", view$bands, view$params %||% list())
  vals <- .preview_bands(img, spec$bands, max_dim)
  native <- natural && .display_native(img, vals)
  arr <- array(0, dim = c(dim(vals)[1], dim(vals)[2], 3L))
  native01 <- function(m) {
    out <- .native01(m)
    out[is.na(out)] <- 0
    out
  }
  if (spec$operation == "rgb") {
    for (k in 1:3) arr[, , k] <- if (native) native01(vals[, , k]) else .stretch01(vals[, , k])
  } else if (native) {
    g <- native01(vals[, , 1])
    for (k in 1:3) arr[, , k] <- g
  } else {
    a <- function(k) vals[, , k]
    den_na <- function(num, den) {
      out <- num / den
      out[den == 0] <- NA_real_
      out
    }
    single <- switch(
      spec$operation,
      single = a(1),
      ratio = den_na(a(1), a(2)),
      normalized_difference = den_na(a(1) - a(2), a(1) + a(2)),
      apply(vals, c(1, 2), mean)
    )
    g <- .stretch01(single)
    for (k in 1:3) arr[, , k] <- g
  }
  attr(arr, "view") <- spec
  arr
}

# Downsampled base image as a PNG data URI. Returns a list with `uri` (NULL on
# failure), `error` (why no image could be encoded, or NULL) and `view_error`
# (why the requested view could not be applied, in which case the default
# natural-colour view was encoded instead).
.image_data_uri_result <- function(img, max_dim = 2048L, view = NULL) {
  if (!requireNamespace("magick", quietly = TRUE)) {
    return(list(uri = NULL, error = "package magick is not installed", view_error = NULL))
  }
  encode <- function(v) {
    arr <- .view_display_array(img, v, max_dim)
    attr(arr, "view") <- NULL
    im <- magick::image_read(arr)
    raw <- magick::image_write(im, format = "png")
    paste0("data:image/png;base64,", gsub("[\r\n]", "", jsonlite::base64_enc(raw)))
  }
  why <- function(e) cli::ansi_strip(conditionMessage(e))
  uri <- tryCatch(encode(view), error = function(e) e)
  if (!inherits(uri, "error")) {
    return(list(uri = uri, error = NULL, view_error = NULL))
  }
  if (is.null(view)) {
    return(list(uri = NULL, error = why(uri), view_error = NULL))
  }
  # A view chosen for another image (e.g. bands beyond this image's count)
  # must not blank the canvas: fall back to the default view and say so.
  fallback <- tryCatch(encode(NULL), error = function(e) e)
  if (inherits(fallback, "error")) {
    return(list(uri = NULL, error = why(fallback), view_error = why(uri)))
  }
  list(uri = fallback, error = NULL, view_error = why(uri))
}

# Why the last .image_data_uri() call produced no image (or did not apply the
# requested view). A side channel, so .image_data_uri() keeps its URI-or-NULL
# contract and stays the single seam that tests and fixtures replace.
.image_display <- new.env(parent = emptyenv())

# Downsampled base image as a PNG data URI, or NULL if it cannot be encoded.
.image_data_uri <- function(img, max_dim = 2048L, view = NULL) {
  res <- .image_data_uri_result(img, max_dim = max_dim, view = view)
  .image_display$error <- res$error
  .image_display$view_error <- res$view_error
  res$uri
}

#' Build a tile-source descriptor for the canvas
#'
#' @param img An [annot_image].
#' @param level_max Optional maximum level to expose; the image maximum by
#'   default.
#' @param tile_size Tile size in pixels. Default `512`.
#' @param embed Logical; embed a downsampled base image as a data URI (for the
#'   self-contained canvas). Default `TRUE`.
#' @param view Optional band view: a list with `operation` (see
#'   [at_band_operations()]), `bands` and `params`. `NULL` shows natural-colour
#'   RGB (nearest bands to 640/550/460 nm for spectral cubes). Display only. A
#'   view that does not apply to `img` (for example bands it does not have)
#'   falls back to the default view and is reported in `viewError`.
#' @param call The calling environment, for error reporting.
#' @return A list describing the image for the widget: `width`, `height`
#'   (level-0 pixels), `nBands`, and the pyramid description `tileSize`,
#'   `minLevel` and `maxLevel` (informational: the built-in canvas displays a
#'   single embedded image rather than streaming tiles). When `embed` is
#'   `TRUE` it also has `dataUri` (a PNG data URI); when no image could be
#'   encoded, `dataUri` is absent and `displayError` says why, and the canvas
#'   shows that message instead of an image. `viewError` says why `view` was
#'   not applied, when it was not.
#' @family shiny
#' @export
at_tile_source <- function(img, level_max = NULL, tile_size = 512L, embed = TRUE,
                           view = NULL, call = rlang::caller_env()) {
  .check_image(img, call = call)
  tile_size <- .check_count(tile_size, min = 1L, call = call)
  d0 <- at_dims(img, 0)
  maxl <- if (is.null(level_max)) img$n_levels - 1L else .check_count(level_max, call = call)
  src <- list(
    width = d0[1], height = d0[2], tileSize = tile_size,
    minLevel = 0L, maxLevel = maxl, nBands = img$n_bands
  )
  if (embed) {
    .image_display$error <- NULL
    .image_display$view_error <- NULL
    src$dataUri <- .image_data_uri(img, view = view)
    if (is.null(src$dataUri)) src$displayError <- if (!requireNamespace("magick", quietly = TRUE))
      "Canvas display requires package magick. Install it with install.packages(\"magick\") and reopen the app."
    else .encode_failure_text(.image_display$error)
    src$viewError <- .image_display$view_error
  }
  src
}

.encode_failure_text <- function(reason = NULL) {
  if (!.is_string(reason) || !nzchar(reason)) {
    return("Could not encode the image for display. Check the image reader and choose another image.")
  }
  paste0("Could not encode the image for display (", sub("[.]$", "", reason),
         "). Check the image reader and choose another image.")
}

# Display projection only: analytical masks and exports retain hidden layers.
# Each feature carries the style the canvas draws with (label colour as
# "#RRGGBB", fill opacity, stroke width, lock state); layers are ordered by
# `z`, so a higher layer is drawn on top and hit first.
.canvas_features <- function(project, layer = NULL) {
  names <- names(project$layers)
  if (!is.null(layer)) names <- intersect(names, layer)
  names <- names[!vapply(project$layers[names], function(x) identical(x$style$visible, FALSE), logical(1))]
  names <- names[order(vapply(project$layers[names], function(x) as.numeric(x$style$z %||% 1), numeric(1)))]
  fc <- .project_to_features(project, names, 0L, FALSE, at_dims(project$image, 0)[2], FALSE)
  fc$features <- lapply(fc$features, function(f) {
    style <- project$layers[[f$properties$layer]]$style
    label <- f$properties$label
    cols <- style$colour
    f$properties$colour <- .canvas_hex(
      if (!is.null(cols) && .is_string(label) && label %in% names(cols)) unname(cols[[label]]) else "#5E2C8E")
    f$properties$fill_alpha <- style$fill_alpha
    f$properties$stroke_width <- style$stroke_width
    f$properties$locked <- isTRUE(style$locked) || isTRUE(f$properties$attributes$locked)
    f$properties$visible <- TRUE
    f
  })
  # .project_to_features retains project ordering; impose the display z order.
  fc$features <- fc$features[order(vapply(fc$features, function(f) match(f$properties$layer, names), integer(1)))]
  fc
}

# Any R colour as "#RRGGBB": canvas styles understand CSS colours, not R names
# such as "grey50".
.canvas_hex <- function(colour) {
  rgb <- tryCatch(grDevices::col2rgb(colour), error = function(e) NULL)
  if (is.null(rgb)) {
    return("#5E2C8E")
  }
  grDevices::rgb(rgb[1, 1], rgb[2, 1], rgb[3, 1], maxColorValue = 255)
}

# The rendered entry and annotation revision, stamped onto every browser event
# so a late event from another image or an older revision is rejected.
.canvas_identity <- function(project) {
  if (is.null(project) || is.null(project$meta$entry_id)) {
    return(NULL)
  }
  list(entry_id = project$meta$entry_id, revision = project$meta$annotation_revision %||% 0)
}

#' An annotation canvas widget
#'
#' The canvas shows one embedded, downsampled image with the project's ROIs
#' drawn in their label colours (hidden layers are left out; locked layers
#' cannot be erased or moved on the canvas). It pans with a drag and zooms
#' with the mouse wheel or a two-finger pinch. When no image can be shown, it
#' says why instead of keeping a previous image.
#'
#' @section Shiny inputs:
#' In Shiny, the canvas with output id `id` sends these inputs. Each value is a
#' list `entry_id`, `revision`, `payload`: the identity rendered when the
#' gesture began (the project's `meta$entry_id` and `meta$annotation_revision`,
#' or the element id and `0` for a project without them) and the event data.
#' A render or [at_canvas_set_annotations()] with a different identity cancels
#' unfinished gestures, and stale events are never sent.
#' \describe{
#'   \item{`<id>_created`}{A drawn GeoJSON feature in level-0 pixels; `target`
#'     holds `options$creationTarget` (`layer`, `label`) as it was when the
#'     drawing began. A click with the rectangle or circle tool is not a shape.}
#'   \item{`<id>_edited`}{`roi_id`, `layer`, `label` and the moved `geometry`
#'     (sent only after an actual drag).}
#'   \item{`<id>_erased`}{The erased ROI id.}
#'   \item{`<id>_selected`}{The ids of the selected ROIs (possibly none).}
#'   \item{`<id>_probed`}{`x`, `y`: the probed level-0 pixel position.}
#'   \item{`<id>_viewport`}{`zoom`, `center_x`, `center_y` and `bounds`
#'     (`xmin`, `ymin`, `xmax`, `ymax` in level-0 pixels) after a pan or zoom.}
#'   \item{`<id>_ready`}{`ready` and `error`: whether the image is displayed.}
#' }
#' A drawn or moved shape is shown dashed until new annotations arrive, and
#' disappears after a few seconds if none do, so the canvas does not keep
#' showing an ROI the app did not accept.
#'
#' @param img An [annot_image] to display.
#' @param project Optional [annot_project] whose ROIs are shown initially.
#' @param tool Initial tool: one of `"pan"`, `"rect"`, `"polygon"`, `"freehand"`,
#'   `"circle"`, `"point"`, `"edit"`, `"erase"`, `"probe"` (emit a pixel
#'   position for spectra) or `"select"` (emit the clicked ROI id).
#' @param width,height Widget dimensions.
#' @param elementId Optional element id.
#' @param options A list of extra options passed to the widget:
#'   `creationTarget` (a list with `layer`, `label` and `locked`; drawing is
#'   refused on a locked target) and `selection` (ROI ids to highlight).
#' @param view Optional band view passed to [at_tile_source()].
#' @param call The calling environment, for error reporting.
#'
#' @return An `htmlwidget` object.
#' @family shiny
#' @seealso [at_canvas_proxy()], [at_tile_source()]
#' @export
#' @examplesIf requireNamespace("htmlwidgets", quietly = TRUE) && requireNamespace("magick", quietly = TRUE)
#' at_canvas(at_example_image("tissue"))
at_canvas <- function(img, project = NULL, tool = "pan", width = NULL,
                      height = NULL, elementId = NULL, options = list(),
                      view = NULL, call = rlang::caller_env()) {
  .check_image(img, call = call)
  .canvas_deps_ok(call = call)
  tool <- .check_choice(tool, .canvas_tool_names, call = call)
  annotations <- if (!is.null(project)) {
    .check_project(project, call = call)
    .canvas_features(project)
  } else {
    list(type = "FeatureCollection", features = list())
  }
  x <- list(
    tileSource = at_tile_source(img, view = view, call = call),
    annotations = annotations,
    identity = .canvas_identity(project),
    tool = tool,
    options = options
  )
  htmlwidgets::createWidget(
    name = "atcanvas", x = x, width = width, height = height,
    package = "hyperannotatR", elementId = elementId,
    sizingPolicy = htmlwidgets::sizingPolicy(defaultWidth = "100%", defaultHeight = 600,
                                             browser.fill = TRUE)
  )
}

#' Shiny output for the annotation canvas
#' @param outputId Output id.
#' @param width,height Output dimensions.
#' @return A Shiny output element.
#' @family shiny
#' @export
atCanvasOutput <- function(outputId, width = "100%", height = "600px") {
  htmlwidgets::shinyWidgetOutput(outputId, "atcanvas", width, height, package = "hyperannotatR")
}

#' Render an annotation canvas in Shiny
#' @param expr An expression producing an [at_canvas()].
#' @param env The environment to evaluate `expr` in.
#' @param quoted Is `expr` already quoted?
#' @return A Shiny render function.
#' @family shiny
#' @export
renderAtCanvas <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) {
    expr <- substitute(expr)
  }
  htmlwidgets::shinyRenderWidget(expr, atCanvasOutput, env, quoted = TRUE)
}

# ---- Proxy (partial updates without re-rendering) --------------------------

#' A proxy for an existing annotation canvas
#'
#' Mirrors the `leafletProxy()` pattern: update a live canvas without
#' re-rendering the whole widget. Inside a Shiny module, pass the module's
#' (un-namespaced) output id; it is namespaced with the module session, as
#' `leaflet::leafletProxy()` does.
#'
#' @param id The canvas output id.
#' @param session The Shiny session.
#' @return An `atcanvas_proxy` object.
#' @family shiny
#' @export
at_canvas_proxy <- function(id, session = shiny::getDefaultReactiveDomain()) {
  .check_string(id)
  id <- .proxy_ns_id(id, session)
  structure(list(id = id, session = session), class = "atcanvas_proxy")
}

# Namespace a module-local output id, so proxy messages reach the element the
# module rendered ("mod-canvas" rather than "canvas"). Already-namespaced ids
# and plain sessions are left alone.
.proxy_ns_id <- function(id, session) {
  ns <- tryCatch(session$ns, error = function(e) NULL)
  if (!is.function(ns)) {
    return(id)
  }
  prefix <- tryCatch(ns(""), error = function(e) "")
  if (!.is_string(prefix) || !nzchar(prefix) || startsWith(id, prefix)) {
    return(id)
  }
  ns(id)
}

.canvas_msg <- function(proxy, method, payload, call = rlang::caller_env()) {
  .check_class(proxy, "atcanvas_proxy", call = call)
  msg <- c(list(id = proxy$id), payload)
  proxy$session$sendCustomMessage(paste0("atcanvas-", method), msg)
  invisible(proxy)
}

#' Replace the annotations on a canvas
#' @param proxy An `atcanvas_proxy`.
#' @param project An [annot_project].
#' @param layer Optional layer filter.
#' @param call The calling environment, for error reporting.
#' @return The proxy, invisibly.
#' @family shiny
#' @export
at_canvas_set_annotations <- function(proxy, project, layer = NULL,
                                      call = rlang::caller_env()) {
  .check_project(project, call = call)
  fc <- .canvas_features(project, layer)
  .canvas_msg(proxy, "set_annotations", list(annotations = fc, identity = .canvas_identity(project)),
              call = call)
}

#' Set the active drawing tool
#' @inheritParams at_canvas_set_annotations
#' @param tool One of the canvas tools.
#' @family shiny
#' @return The proxy, invisibly.
#' @export
at_canvas_set_tool <- function(proxy, tool, call = rlang::caller_env()) {
  tool <- .check_choice(tool, .canvas_tool_names, call = call)
  .canvas_msg(proxy, "set_tool", list(tool = tool), call = call)
}

#' Highlight selected ROIs on a canvas
#' @inheritParams at_canvas_set_annotations
#' @param roi_ids Character vector of ROI ids to highlight (empty clears).
#' @family shiny
#' @return The proxy, invisibly.
#' @export
at_canvas_set_selection <- function(proxy, roi_ids = character(), call = rlang::caller_env()) {
  if (!is.character(roi_ids)) {
    .at_abort("{.arg roi_ids} must be a character vector.", call = call)
  }
  .canvas_msg(proxy, "set_selection", list(roi_ids = as.list(roi_ids)), call = call)
}

#' Set the displayed band or RGB triple
#'
#' Retained for API compatibility; it has no visible effect on the built-in
#' canvas. The canvas shows one embedded image rendered in R, and cannot
#' recompute bands in the browser. To change the displayed bands, re-render the
#' widget with a `view` (see [at_canvas()] and [at_band_view()]), as the
#' annotation app does.
#'
#' @inheritParams at_canvas_set_annotations
#' @param band A band index or a length-3 vector of band indices.
#' @family shiny
#' @return The proxy, invisibly.
#' @export
at_canvas_set_band <- function(proxy, band, call = rlang::caller_env()) {
  .canvas_msg(proxy, "set_band", list(band = as.integer(band)), call = call)
}

#' Overlay a mask on the canvas
#' @inheritParams at_canvas_set_annotations
#' @param mask An `annot_mask`.
#' @param alpha Overlay opacity. Default `0.5`.
#' @family shiny
#' @return The proxy, invisibly.
#' @export
at_canvas_set_overlay <- function(proxy, mask, alpha = 0.5,
                                  call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  .check_number(alpha, min = 0, max = 1, call = call)
  uri <- .mask_data_uri(mask)
  .canvas_msg(proxy, "set_overlay", list(overlay = uri, alpha = alpha), call = call)
}

# Encode a mask preview to a coloured PNG data URI. Colours follow the
# membership-aware display legend: a bitfield pixel carrying several classes
# gets the mean of their colours instead of staying transparent, and
# background pixels stay transparent.
.mask_data_uri <- function(mask, max_dim = 1024L) {
  if (!requireNamespace("magick", quietly = TRUE)) {
    return(NULL)
  }
  pv <- at_mask_preview(mask, max_dim = max_dim)
  m <- as.matrix(pv)
  lg <- .mask_display(pv)
  arr <- array(0, dim = c(nrow(m), ncol(m), 4L))
  if (length(lg$value) > 0L) {
    for (k in seq_along(lg$value)) {
      col <- grDevices::col2rgb(lg$colour[k]) / 255
      sel <- m == lg$value[k]
      sel[is.na(sel)] <- FALSE
      arr[, , 1][sel] <- col[1]
      arr[, , 2][sel] <- col[2]
      arr[, , 3][sel] <- col[3]
      arr[, , 4][sel] <- 1
    }
  }
  im <- magick::image_read(arr)
  raw <- magick::image_write(im, format = "png")
  paste0("data:image/png;base64,", gsub("[\r\n]", "", jsonlite::base64_enc(raw)))
}

#' Zoom the canvas to a bounding box
#' @inheritParams at_canvas_set_annotations
#' @param bbox Optional `c(xmin, ymin, xmax, ymax)` in level-0 pixels; fits the
#'   whole image when `NULL`.
#' @family shiny
#' @return The proxy, invisibly.
#' @export
at_canvas_fit <- function(proxy, bbox = NULL, call = rlang::caller_env()) {
  .canvas_msg(proxy, "fit_bounds", list(bbox = if (is.null(bbox)) NULL else as.numeric(bbox)),
              call = call)
}
