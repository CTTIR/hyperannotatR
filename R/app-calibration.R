# Calibration references are independent, two-endpoint measurements. Their
# coordinates remain in image pixels; a reference annotation never assigns a
# physical pixel size. Summaries and provisional scales are recomputed from
# saved ROI geometry; assumed reference sizes remain explicitly unverified.
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
    .at_abort(paste("Use Distance: choose two distinct endpoints",
                    "inside the image for a calibration reference."),
              class = "validation", code = "CALIBRATION_SEGMENT")
  }
  roi
}

.reference_mm <- function(value) {
  if (!is.numeric(value) || length(value) != 1L ||
      !is.finite(value) || value <= 0) NA_real_ else value
}

.reference_lookup <- function(values, label) {
  .reference_mm(if (is.list(values)) values[[label]] else NULL)
}

# Session defaults are copied into a project's metadata when materialising or
# saving it, so standalone project exports retain the effective default too.
.calibration_project_defaults <- function(project, defaults) {
  if (!is.null(defaults)) project$meta$calibration_defaults_mm <- defaults
  project
}

.calibration_defaults <- function(rv) {
  st <- .app_live_store(rv)
  if (is.null(st)) return(rv$session$meta$calibration_defaults_mm %||%
                           rv$project$meta$calibration_defaults_mm)
  if (is.function(st$calibration_revision)) st$calibration_revision()
  st$session$meta$calibration_defaults_mm %||%
    rv$project$meta$calibration_defaults_mm
}

.calibration_reference <- function(project, layer, label,
                                   defaults = project$meta$calibration_defaults_mm) {
  meta <- project$layers[[layer]]$meta
  global <- .reference_lookup(if (is.list(defaults)) defaults[[layer]] else NULL, label)
  if (!is.finite(global)) global <- .reference_lookup(meta$reference_assumptions_mm, label)
  override <- .reference_lookup(meta$reference_overrides_mm, label)
  list(global_mm = global, override_mm = override,
       effective_mm = if (is.finite(override)) override else global,
       source = if (is.finite(override)) "image" else "global")
}

.calibration_summary <- function(project, layer, label,
                                 defaults = project$meta$calibration_defaults_mm) {
  rois <- Filter(function(r) identical(r$label, label),
                 project$layers[[layer]]$rois)
  lengths <- vapply(rois, .calibration_length, 0, image = project$image)
  names(lengths) <- vapply(rois, `[[`, "", "id")
  valid <- is.finite(lengths)
  lengths_px <- lengths[valid]
  n <- length(lengths_px)
  reference <- .calibration_reference(project, layer, label, defaults)
  assumed <- reference$effective_mm
  list(n = n, lengths_px = lengths_px, excluded = sum(!valid),
       mean_px = if (n >= 3L) mean(lengths_px) else NA_real_,
       sd_px = if (n >= 3L) stats::sd(lengths_px) else NA_real_,
       assumed_length_mm = assumed,
       reference_source = reference$source,
       estimated_mm_per_px = if (n >= 3L) assumed / mean(lengths_px) else NA_real_,
       status = if (n < 3L) "insufficient" else
         if (n < 5L) "minimum" else "recommended")
}

.calibration_set_global <- function(rv, layer, label, value) {
  defaults <- .calibration_defaults(rv) %||% list()
  if (identical(defaults[[layer]][[label]], value)) return(invisible(FALSE))
  defaults[[layer]][[label]] <- value
  sess <- rv$session
  sess$meta$calibration_defaults_mm <- defaults
  rv$session <- sess
  st <- .app_live_store(rv)
  if (!is.null(st)) {
    st$session$meta$calibration_defaults_mm <- defaults
    st$calibration_revision(shiny::isolate(st$calibration_revision()) + 1)
  }
  .state_changed(rv, .calibration_project_defaults(rv$project, defaults),
                 action = "calibration_default")
}

.calibration_server <- function(input, output, session, rv) {
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

  output$calibration_settings <- shiny::renderUI({
    shiny::req(rv$project, rv$active_layer, rv$active_label)
    layer <- rv$project$layers[[rv$active_layer]]
    if (!.is_calibration_layer(layer)) return(NULL)
    reference <- .calibration_reference(rv$project, rv$active_layer,
      rv$active_label, .calibration_defaults(rv))
    ns <- session$ns
    fields <- list(layer = "layers-layer", label = "layers-label")
    shiny::tags$fieldset(
      disabled = if (isTRUE(rv$read_only) || isTRUE(layer$style$locked)) "disabled",
      class = "at-reference-settings",
      shiny::fluidRow(
        shiny::column(6,
          shiny::numericInput(ns("calibration_global_mm"),
            "Global reference length (mm)", reference$global_mm, min = 0, step = "any"),
          .at_action(ns("calibration_global_apply"), "Apply globally",
            class = "btn-sm",
            fields = c(fields, list(value = ns("calibration_global_mm"))))),
        shiny::column(6,
          shiny::numericInput(ns("calibration_image_mm"),
            "Image reference length (mm)", reference$effective_mm, min = 0, step = "any"),
          shiny::div(class = "at-reference-actions",
            .at_action(ns("calibration_image_apply"), "Apply to image",
              class = "btn-sm",
              fields = c(fields, list(value = ns("calibration_image_mm")))),
            .at_action(ns("calibration_reset"), "Use global default",
              class = "btn-sm", fields = fields)))),
      shiny::p(class = "at-progress",
        "Applies to the selected reference label. Global changes preserve image overrides."))
  })

  apply_reference <- function(value, scope) {
    fields <- c("layer", "label", if (scope != "reset") "value")
    event <- .state_event(rv, value, fields = fields)
    if (is.null(event) || !.state_matches(rv, event) ||
        !isTRUE(rv$display_ready) || isTRUE(rv$read_only)) return()
    st <- rv$store
    if (!is.null(st) && !identical(st$generation, rv$session_generation)) return()
    target <- event$payload
    if (!identical(target$layer, rv$active_layer) ||
        !identical(target$label, rv$active_label)) return()
    layer <- rv$project$layers[[target$layer]]
    if (!.is_calibration_layer(layer) || isTRUE(layer$style$locked) ||
        !target$label %in% layer$labels) return()
    mm <- if (scope != "reset") suppressWarnings(as.numeric(target$value))
    if (scope != "reset" && !is.finite(.reference_mm(mm))) {
      .app_notify("Enter a reference length greater than zero in mm.", type = "error")
      return()
    }
    if (scope == "global") {
      .calibration_set_global(rv, target$layer, target$label, mm)
    } else {
      .state_mutate(rv, function(p) {
        values <- p$layers[[target$layer]]$meta$reference_overrides_mm %||% list()
        values[[target$label]] <- mm
        p$layers[[target$layer]]$meta$reference_overrides_mm <- values
        p
      }, event, action = "calibration_override")
    }
  }
  shiny::observeEvent(input$calibration_global_apply,
    apply_reference(input$calibration_global_apply, "global"))
  shiny::observeEvent(input$calibration_image_apply,
    apply_reference(input$calibration_image_apply, "image"))
  shiny::observeEvent(input$calibration_reset,
    apply_reference(input$calibration_reset, "reset"))

  output$calibration_summary <- shiny::renderUI({
    shiny::req(rv$project, rv$active_layer, rv$active_label)
    layer <- rv$project$layers[[rv$active_layer]]
    if (!.is_calibration_layer(layer)) return(NULL)
    s <- .calibration_summary(rv$project, rv$active_layer, rv$active_label,
                              .calibration_defaults(rv))
    progress <- switch(s$status,
      insufficient = "At least 3 measurements required; 5 recommended.",
      minimum = "Minimum reached; 5 measurements recommended.",
      recommended = "Recommended number reached.")
    shiny::div(class = "at-calibration",
      shiny::strong(sprintf("Calibration: %d / 5 measurements", s$n)),
      shiny::p(progress),
      if (s$n >= 3L) shiny::p(shiny::strong(sprintf(
        "Mean reference length: %.2f px; SD: %.2f px", s$mean_px, s$sd_px))),
      if (is.finite(s$assumed_length_mm)) shiny::p(sprintf(
        "Assumed reference length: %.2f mm (unverified).", s$assumed_length_mm)),
      if (is.finite(s$assumed_length_mm)) shiny::p(
        if (s$reference_source == "image") "Reference source: Image override."
        else "Reference source: Global default."),
      if (is.finite(s$estimated_mm_per_px)) shiny::p(shiny::strong(sprintf(
        "Estimated scale: %.5f mm/px", s$estimated_mm_per_px))),
      if (s$n) shiny::tags$details(shiny::tags$summary("Measurements (px)"),
        paste(sprintf("%.2f", s$lengths_px), collapse = ", ")),
      if (s$excluded) shiny::p(sprintf(
        "%d existing ROI(s) excluded: use distinct endpoints; copied or area ROIs are not repeats.",
        s$excluded)),
      shiny::p(class = "at-progress",
        if (is.finite(s$assumed_length_mm))
          "The estimated scale assumes square pixels and the stated reference size. Stored geometry remains in pixels."
        else
          "Repeat the same reference dimension in this image. Its known physical size is required for mm calibration."))
  })
}
