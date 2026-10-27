# Calibration references are independent, two-endpoint measurements. Their
# coordinates remain in image pixels; a reference annotation never assigns a
# physical pixel size. Summaries are recomputed from saved ROI geometry.
.is_calibration_layer <- function(layer) {
  identical(layer$meta$role, "calibration_reference")
}

.calibration_length <- function(roi, image) {
  if (identical(roi$source, "copied")) return(NA_real_)
  g <- roi$geometry[[1]]
  if (!inherits(g, "LINESTRING") || nrow(g) != 2L ||
      ncol(g) != 2L || any(!is.finite(g))) return(NA_real_)
  g <- unclass(at_transform(roi, to_level = 0L, img = image)$geometry[[1]])
  dims <- at_dims(image)
  if (any(g < 0) || any(g[, 1] > dims[1]) || any(g[, 2] > dims[2])) {
    return(NA_real_)
  }
  distance <- sqrt(sum((g[2, ] - g[1, ])^2))
  if (is.finite(distance) && distance > 0) distance else NA_real_
}

.calibration_validate_roi <- function(layer, roi, image) {
  if (.is_calibration_layer(layer) &&
      !is.finite(.calibration_length(roi, image))) {
    .at_abort(paste("Use Line / distance: choose two distinct endpoints",
                    "inside the image for a calibration reference."),
              class = "validation", code = "CALIBRATION_SEGMENT")
  }
  roi
}

.calibration_summary <- function(project, layer, label) {
  rois <- Filter(function(r) identical(r$label, label),
                 project$layers[[layer]]$rois)
  lengths <- vapply(rois, .calibration_length, 0, image = project$image)
  names(lengths) <- vapply(rois, `[[`, "", "id")
  valid <- is.finite(lengths)
  lengths_px <- lengths[valid]
  n <- length(lengths_px)
  list(n = n, lengths_px = lengths_px, excluded = sum(!valid),
       mean_px = if (n >= 3L) mean(lengths_px) else NA_real_,
       sd_px = if (n >= 3L) stats::sd(lengths_px) else NA_real_,
       status = if (n < 3L) "insufficient" else
         if (n < 5L) "minimum" else "recommended")
}

.calibration_server <- function(output, rv) {
  previous_tool <- shiny::reactiveVal(NULL)
  shiny::observeEvent(list(rv$active_layer, rv$entry_id), {
    layer <- rv$project$layers[[rv$active_layer]]
    if (.is_calibration_layer(layer) && !isTRUE(rv$read_only) &&
        !isTRUE(layer$style$locked)) {
      if (is.null(previous_tool())) previous_tool(rv$tool %||% "pan")
      rv$tool <- "line"
    } else if (!is.null(previous_tool())) {
      if (identical(rv$tool, "line")) rv$tool <- previous_tool()
      previous_tool(NULL)
    }
  }, ignoreInit = FALSE)

  output$calibration_summary <- shiny::renderUI({
    shiny::req(rv$project, rv$active_layer, rv$active_label)
    layer <- rv$project$layers[[rv$active_layer]]
    if (!.is_calibration_layer(layer)) return(NULL)
    s <- .calibration_summary(rv$project, rv$active_layer, rv$active_label)
    progress <- switch(s$status,
      insufficient = "At least 3 measurements required; 5 recommended.",
      minimum = "Minimum reached; 5 measurements recommended.",
      recommended = "Recommended number reached.")
    shiny::div(class = "at-calibration",
      shiny::strong(sprintf("Calibration: %d / 5 measurements", s$n)),
      shiny::p(progress),
      if (s$n >= 3L) shiny::p(shiny::strong(sprintf(
        "Mean reference length: %.2f px; SD: %.2f px", s$mean_px, s$sd_px))),
      if (s$n) shiny::tags$details(shiny::tags$summary("Measurements (px)"),
        paste(sprintf("%.2f", s$lengths_px), collapse = ", ")),
      if (s$excluded) shiny::p(sprintf(
        "%d existing ROI(s) excluded: use distinct endpoints; copied or area ROIs are not repeats.",
        s$excluded)),
      shiny::p(class = "at-progress",
        "Repeat the same reference dimension in this image. Its known physical size is required for mm calibration."))
  })
}
