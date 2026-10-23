# Shiny modules of the annotation app. All app code lives in R/ so the app can
# be built and tested as an object (at_app()) without sourcing files from
# inst/; inst/ only holds static assets. Every module receives the shared
# reactiveValues `rv` documented in app-builder.R; annotation changes go
# through the identity-checked transitions in app-state.R. Internal.

# ---- Shared helpers ------------------------------------------------------------

.first_label <- function(labs) {
  labs <- labs[!is.na(labs) & nzchar(labs)]
  if (length(labs)) labs[1] else NULL
}

# Run `expr`; on error notify instead of ending the Shiny session.
.app_try <- function(expr, what = "The action") {
  tryCatch(expr, error = function(e) {
    shiny::showNotification(paste(what, "failed:", .app_error_text(e)), type = "error")
    invisible(FALSE)
  })
}

# A form label read by screen readers but not shown (Bootstrap 5).
.sr_label <- function(text) shiny::span(class = "visually-hidden", text)

# A blank plot carrying a message (for outputs that cannot be drawn).
.message_plot <- function(text) {
  ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0.5, y = 0.5, label = text, size = 3.5) +
    ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1) +
    ggplot2::theme_void()
}

# Export stems of the queue (one per entry, unique and path-safe).
.app_stems <- function(session) {
  m <- session$manifest
  if ("export_stem" %in% names(m)) m$export_stem else .unique_components(.safe_component(m$name))
}

# `path` with symbolic links resolved as far as it exists (e.g. macOS /var
# is /private/var), so prefixes compare reliably for paths not yet created.
.app_real_path <- function(path) {
  if (file.exists(path) || identical(dirname(path), path)) {
    return(normalizePath(path, winslash = "/", mustWork = FALSE))
  }
  file.path(.app_real_path(dirname(path)), basename(path))
}

.app_path_within <- function(path, root) {
  p <- .app_real_path(path)
  r <- sub("/+$", "", .app_real_path(root))
  identical(p, r) || startsWith(p, paste0(r, "/"))
}

# Is `path` inside R's temporary directory (deleted when R exits)?
.app_is_temp <- function(path) {
  .is_string(path) && .app_path_within(path, tempdir())
}

# Paths typed into the app (Data page) must lie under
# `getOption("hyperannotatR.app_root")` when that option is set; without it every
# path the R process can read is accepted, which suits local use only.
.app_path_allowed <- function(path) {
  root <- getOption("hyperannotatR.app_root", default = NULL)
  is.null(root) || .app_path_within(path, root)
}

.data_exts <- "\\.(dat|hdr|tif|tiff|png|jpe?g|qptiff|cu3|cu3s)$"

# Image files under `dir`, breadth first and bounded in depth and count. An
# ENVI payload whose header is also listed is dropped (the header opens the
# pair); a folder holding TIVITA SpecCubes lists only the cubes.
.app_list_images <- function(dir, pattern = .data_exts, max_depth = 4L, max_files = 5000L) {
  found <- character()
  queue <- list(list(path = dir, depth = 0L))
  while (length(queue) && length(found) < max_files) {
    cur <- queue[[1]]
    queue <- queue[-1]
    entries <- list.files(cur$path, full.names = TRUE, no.. = TRUE)
    is_dir <- dir.exists(entries)
    found <- c(found, entries[!is_dir & grepl(pattern, basename(entries), ignore.case = TRUE)])
    if (cur$depth < max_depth) {
      for (d in entries[is_dir]) queue[[length(queue) + 1L]] <- list(path = d, depth = cur$depth + 1L)
    }
  }
  truncated <- length(found) >= max_files
  found <- sort(utils::head(found, max_files))
  cubes <- found[grepl("_SpecCube\\.dat$", found, ignore.case = TRUE)]
  if (length(cubes)) {
    found <- cubes
  } else {
    low <- tolower(found)
    is_dat <- grepl("\\.dat$", low)
    has_hdr <- paste0(low, ".hdr") %in% low | paste0(sub("\\.dat$", "", low), ".hdr") %in% low
    found <- found[!(is_dat & has_hdr)]
  }
  attr(found, "truncated") <- truncated
  found
}

# ---- Queue -------------------------------------------------------------------

.status_glyph <- function(status) {
  c(pending = "\u25cb", in_progress = "\u25d0", complete = "\u2713",
    flagged = "\u2691", skipped = "\u2298")[status]
}

mod_queue_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::div(
      class = "at-queue-controls",
      shiny::selectInput(ns("filter"), .sr_label("Show queue entries with status"),
                         choices = c("all", "pending", "in_progress", "complete", "flagged", "skipped"),
                         selected = "all", selectize = FALSE),
      .at_action(ns("prev"), "\u25c0", `aria-label` = "previous image"),
      .at_action(ns("nxt"), "\u25b6", `aria-label` = "next image"),
      .at_action(ns("next_pending"), "Next pending")
    ),
    shiny::tableOutput(ns("list")),
    shiny::div(class = "at-progress", shiny::textOutput(ns("progress")))
  )
}

mod_queue_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    .state_init(rv)
    shiny::observeEvent(input$nxt, {
      .state_navigate(rv, rv$cursor + 1L, .state_event(rv, input$nxt))
    })
    shiny::observeEvent(input$prev, {
      .state_navigate(rv, rv$cursor - 1L, .state_event(rv, input$prev))
    })
    shiny::observeEvent(input$next_pending, {
      .state_navigate(rv, .state_pending(rv), .state_event(rv, input$next_pending))
    })
    output$list <- shiny::renderTable({
      m <- at_session_status(rv$session)
      n <- m$n_rois
      # Live count for the image being edited.
      if (!is.null(rv$project) && rv$cursor >= 1L && rv$cursor <= length(n)) {
        n[rv$cursor] <- nrow(at_rois(rv$project))
      }
      keep <- if (!is.null(input$filter) && input$filter != "all") m$status == input$filter else rep(TRUE, nrow(m))
      data.frame(idx = m$idx[keep], name = m$name[keep],
                 status = .status_glyph(m$status[keep]), n = n[keep])
    })
    output$progress <- shiny::renderText({
      m <- at_session_status(rv$session)
      sprintf("%d / %d complete", sum(m$status == "complete"), nrow(m))
    })
    # Keep the queue status current even while another page is in front, so ROI
    # counts and statuses are up to date the moment you return to Annotate.
    shiny::outputOptions(output, "list", suspendWhenHidden = FALSE)
    shiny::outputOptions(output, "progress", suspendWhenHidden = FALSE)
  })
}

# ---- Layers and labels ---------------------------------------------------------

.at_label_palette <- c("#e69f00", "#56b4e9", "#009e73", "#f0e442",
                       "#0072b2", "#d55e00", "#cc79a7", "#999999")

mod_layers_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Layers"),
    shiny::uiOutput(ns("layer_sel")),
    shiny::div(
      class = "at-add-row",
      shiny::textInput(ns("new_layer"), "New layer name", placeholder = "new layer name"),
      .at_action(ns("add_layer"), "+ layer", fields = list(new_layer = ns("new_layer")))
    ),
    shiny::h5("Labels"),
    shiny::uiOutput(ns("label_sel")),
    shiny::div(
      class = "at-add-row",
      shiny::textInput(ns("new_label"), "New label name", placeholder = "new label name"),
      .at_action(ns("add_label"), "+ label",
                 fields = list(new_label = ns("new_label"), layer = ns("layer")))
    )
  )
}

mod_layers_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    .state_init(rv)
    output$layer_sel <- shiny::renderUI({
      shiny::req(rv$project)
      shiny::radioButtons(session$ns("layer"), "Layer",
                          choices = stats::setNames(names(rv$project$layers), vapply(rv$project$layers, function(layer) paste0(layer$name,
                            if (isTRUE(layer$style$locked)) " (locked)" else "",
                            if (identical(layer$style$visible, FALSE)) " (hidden)" else ""), character(1))),
                          selected = shiny::isolate(rv$active_layer))
    })
    output$label_sel <- shiny::renderUI({
      shiny::req(rv$project, rv$active_layer)
      lyr <- rv$project$layers[[rv$active_layer]]
      labs <- lyr$labels
      if (length(labs) == 0L) {
        return(shiny::div(class = "at-progress", "No labels yet \u2014 add one below to start drawing."))
      }
      shiny::radioButtons(session$ns("label"), "Label", choices = labs,
                          selected = shiny::isolate(rv$active_label))
    })
    shiny::observeEvent(rv$active_layer, {
      shiny::updateRadioButtons(session, "layer", selected = rv$active_layer)
    })
    shiny::observeEvent(rv$active_label, {
      shiny::updateRadioButtons(session, "label", selected = rv$active_label)
    })
    shiny::observeEvent(input$layer_intent, {
      event <- .state_event(rv, input$layer_intent, fields = c("value"))
      shiny::req(event, event$payload$value %in% names(rv$project$layers))
      if (identical(rv$active_layer, event$payload$value)) return()
      rv$active_layer <- event$payload$value
      # Follow the layer's first label when switching layers.
      rv$active_label <- .first_label(rv$project$layers[[event$payload$value]]$labels)
    })
    shiny::observeEvent(input$label_intent, {
      event <- .state_event(rv, input$label_intent, fields = c("value", "layer"))
      shiny::req(event, identical(event$payload$layer, rv$active_layer),
                 event$payload$value %in% rv$project$layers[[rv$active_layer]]$labels)
      rv$active_label <- event$payload$value
    })

    # Add a custom layer (with a starter label = its name, so it is immediately
    # usable) and make it active.
    shiny::observeEvent(input$add_layer, {
      event <- .state_event(rv, input$add_layer, fields = c("new_layer"))
      shiny::req(event, rv$project, !identical(rv$display_ready, FALSE))
      nm <- trimws(event$payload$new_layer %||% "")
      if (nzchar(nm) && !(nm %in% names(rv$project$layers))) {
        if (.state_mutate(rv, function(p) at_add_layer(p, at_layer(nm, labels = nm)), event,
                          action = "add_layer")) {
          rv$active_layer <- nm
          rv$active_label <- nm
        }
        shiny::updateTextInput(session, "new_layer", value = "")
      }
    })

    # Add a custom label to the clicked layer's vocabulary, give it a colour,
    # and select it.
    shiny::observeEvent(input$add_label, {
      event <- .state_event(rv, input$add_label, fields = c("new_label", "layer"))
      shiny::req(event, rv$project, rv$active_layer, !identical(rv$display_ready, FALSE))
      layer <- event$payload$layer
      shiny::req(is.character(layer), length(layer) == 1L, layer %in% names(rv$project$layers),
                 !isTRUE(rv$project$layers[[layer]]$style$locked))
      new_lab <- trimws(event$payload$new_label %||% "")
      if (!nzchar(new_lab)) return()
      lyr <- rv$project$layers[[layer]]
      if (!(new_lab %in% lyr$labels)) {
        lyr$labels <- c(lyr$labels, new_lab)
        cols <- lyr$style$colour
        if (is.null(cols)) cols <- character(0)
        if (!(new_lab %in% names(cols))) {
          cols[new_lab] <- .at_label_palette[(length(cols) %% length(.at_label_palette)) + 1L]
        }
        lyr$style$colour <- cols
        .state_mutate(rv, function(p) {
          p$layers[[layer]] <- lyr
          p
        }, event, action = "add_label")
        if (identical(layer, rv$active_layer)) rv$active_label <- new_lab
        shiny::updateTextInput(session, "new_label", value = "")
      }
    })
  })
}

# ---- Canvas -----------------------------------------------------------------------

.canvas_tools <- c("pan", "rect", "polygon", "freehand", "circle", "point", "reflection", "edit", "erase",
                   "probe", "select")
.read_only_tools <- c("pan", "probe", "select")

mod_canvas_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::div(
      class = "at-toolbar", role = "toolbar", `aria-label` = "drawing tools",
      lapply(.canvas_tools, function(t) .at_action(ns(paste0("tool_", t)),
        switch(t, circle = "Round area", reflection = "Reflection wand", t),
        `aria-pressed` = "false")),
      .at_action(ns("undo"), "Undo"), .at_action(ns("redo"), "Redo"),
      .at_action(ns("copy"), "Copy previous")
    ),
    shiny::conditionalPanel("output.tool == 'point'", ns = ns,
      shiny::selectInput(ns("point_radius"), "Point marker size (display only)",
        c("Small - 4 px" = 2, "Medium - 8 px" = 4, "Large - 16 px" = 8), selected = 4)),
    shiny::conditionalPanel("output.tool == 'circle'", ns = ns,
      shiny::selectInput(ns("circle_radius"), "Round area diameter (image pixels)",
        c("Small - 5 px" = 2.5, "Medium - 10 px" = 5,
          "Large - 20 px" = 10, "Drag to size" = 0), selected = 5)),
    shiny::conditionalPanel("output.tool == 'reflection'", ns = ns,
      shiny::selectInput(ns("reflection_tolerance"), "Reflection extent",
        c("Tight" = 0.04, "Normal" = 0.1, "Broad" = 0.18), selected = 0.1),
      shiny::p(class = "at-progress",
        "Choose your reflection label, then click a bright reflection. Review the dashed outline: pale tissue can also appear bright."),
      shiny::uiOutput(ns("reflection_review"))),
    shiny::p(class = "at-progress", "Focus the canvas with Tab. Arrows move 1 image pixel (Shift: 10). Enter or Space places a point or fixed round area, or anchors a rectangle; polygon: Space adds a vertex, Enter finishes. Escape cancels. Shift+Enter saves, completes and advances."),
    shiny::div(role = "status", `aria-live` = "polite", class = "atcanvas-status",
               shiny::textOutput(ns("display"))),
    shiny::div(
      role = "region", `aria-label` = "Image annotation canvas",
      atCanvasOutput(ns("canvas"), height = "620px")
    )
  )
}

# Turn a drawn GeoJSON feature (level-0 pixels) into an annot_roi.
.feature_to_roi <- function(feature, label, level = 0L) {
  roi <- at_roi_from_geojson(feature, label = label, level = level)
  radius <- feature$properties$attributes$point_radius
  if (!is.null(radius) && identical(feature$geometry$type, "Point")) {
    if (!is.numeric(radius) || length(radius) != 1L ||
        !is.finite(radius) || radius <= 0 || radius > 100) {
      .at_abort("Point marker radius must be a number between 0 and 100.",
                class = "validation", code = "POINT_SIZE")
    }
    roi$attributes$point_radius <- radius
  }
  roi
}

# Copy every ROI of `from` into `to` as fresh, editable ROIs (new ids,
# source = "copied"). This powers the Shift+V copy-forward throughput feature.
# A locked target layer is left unchanged.
.copy_forward <- function(from, to) {
  for (nm in names(from$layers)) {
    if (!(nm %in% names(to$layers))) {
      to <- at_add_layer(to, at_layer(nm, labels = from$layers[[nm]]$labels))
    }
    if (isTRUE(to$layers[[nm]]$style$locked)) next
    for (r in from$layers[[nm]]$rois) {
      cp <- at_roi_from_sf(r$geometry, label = r$label, level = r$level, source = "copied")
      cp$attributes$point_radius <- r$attributes$point_radius
      to <- at_add_roi(to, nm, cp)
    }
  }
  to
}

# The previous entry's project in memory, for copy-forward.
.previous_project <- function(rv) {
  if (rv$cursor <= 1L) {
    return(NULL)
  }
  rv$session$projects[[rv$cursor - 1L]]
}

mod_canvas_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    .state_init(rv)
    proxy <- at_canvas_proxy("canvas", session = session)
    .reflection_server(input, output, session, rv)
    output$tool <- shiny::renderText(rv$tool %||% "pan")
    shiny::outputOptions(output, "tool", suspendWhenHidden = FALSE)
    shiny::observeEvent(input$point_radius, {
      if (input$point_radius %in% c("2", "4", "8"))
        rv$point_radius <- as.numeric(input$point_radius)
    })
    shiny::observeEvent(input$circle_radius, {
      if (input$circle_radius %in% c("0", "2.5", "5", "10"))
        rv$circle_radius <- as.numeric(input$circle_radius)
    })
    # Render on image / ROI / tool / band-view change. The widget caches the
    # base image by data URI and keeps the viewport, so an ROI edit redraws
    # the overlay only. The identity and the drawing target travel with the
    # render, so gestures report the entry and label they were made on.
    output$canvas <- renderAtCanvas({
      if (is.null(rv$project)) return(htmlwidgets::createWidget("atcanvas",
        x = list(tileSource = list(width = 1, height = 1, displayError = rv$display_error),
          identity = .state_stamp(rv), annotations = list(features = list()), tool = "pan"),
        package = "hyperannotatR", dependencies = .canvas_dependencies()))
      at_canvas(rv$project$image, project = rv$project, tool = rv$tool %||% "pan",
                view = rv$view,
                options = list(
                  pointRadius = rv$point_radius %||% 4,
                  circleRadius = rv$circle_radius %||% 5,
                  suggestion = .reflection_preview_feature(rv),
                  selection = as.list(rv$selection %||% character()),
                  creationTarget = list(
                    layer = rv$active_layer, label = rv$active_label,
                    locked = isTRUE(rv$read_only) ||
                      isTRUE(rv$project$layers[[rv$active_layer]]$style$locked))))
    })
    output$display <- shiny::renderText({
      paste(rv$session$manifest$name[rv$cursor], "\u2014",
        if (isTRUE(rv$display_ready)) "Image ready" else rv$display_error %||% "Waiting for display")
    })
    shiny::observeEvent(input$canvas_ready, {
      event <- .state_event(rv, input$canvas_ready, widget = TRUE)
      shiny::req(event)
      rv$display_ready <- isTRUE(event$payload$ready) && !is.null(rv$project)
      rv$display_error <- if (rv$display_ready) NULL else event$payload$error %||% "Image display unavailable."
      # A render for a new entry clears the overlay; send the app's overlay
      # again. Switching it off has its own observer, so a ready display never
      # clears an overlay the app did not set (e.g. one sent by a proxy).
      if (rv$display_ready && isTRUE(rv$overlay_on)) send_overlay()
    })
    shiny::outputOptions(output, "canvas", suspendWhenHidden = FALSE)

    # Highlight the active tool button (colour and aria-pressed).
    shiny::observeEvent(rv$tool, {
      for (t in .canvas_tools) {
        on <- identical(rv$tool, t)
        shinyjs::toggleClass(id = paste0("tool_", t), class = "active", condition = on)
        shinyjs::runjs(sprintf(
          "var b=document.getElementById('%s'); if (b) b.setAttribute('aria-pressed','%s');",
          session$ns(paste0("tool_", t)), if (on) "true" else "false"))
      }
    }, ignoreInit = FALSE)

    for (t in .canvas_tools) {
      local({
        tool <- t
        shiny::observeEvent(input[[paste0("tool_", tool)]], {
          event <- .state_event(rv, input[[paste0("tool_", tool)]])
          shiny::req(event)
          if (isTRUE(rv$read_only) && !tool %in% .read_only_tools) {
            shiny::showNotification("Read-only session: drawing tools are disabled.", type = "warning")
            return()
          }
          rv$tool <- tool
        })
      })
    }

    send_overlay <- function() {
      if (isTRUE(rv$overlay_on) && !is.null(rv$project)) {
        m <- tryCatch(.current_mask(rv), error = function(e) NULL)
        if (!is.null(m)) at_canvas_set_overlay(proxy, m, alpha = rv$overlay_alpha %||% 0.5)
      } else {
        .canvas_msg(proxy, "clear_overlay", list())
      }
    }
    # The widget shows a gesture before the server decides; a refused one
    # must not stay on screen.
    resend <- function() {
      if (!is.null(rv$project)) try(at_canvas_set_annotations(proxy, rv$project), silent = TRUE)
      invisible(FALSE)
    }

    shiny::observeEvent(input$undo, .state_undo(rv, event = .state_event(rv, input$undo)))
    shiny::observeEvent(input$redo, .state_undo(rv, redo = TRUE, event = .state_event(rv, input$redo)))
    shiny::observeEvent(input$copy, {
      event <- .state_event(rv, input$copy)
      previous <- .previous_project(rv)
      shiny::req(event, previous)
      .state_mutate(rv, function(p) .copy_forward(previous, p), event, action = "paste_forward")
    })
    # Decode identity/revision before parsing geometry or touching history.
    shiny::observeEvent(input$canvas_created, {
      event <- .state_event(rv, input$canvas_created, widget = TRUE)
      shiny::req(event, rv$project, is.list(event$payload))
      target <- event$payload$target
      ok <- is.list(target) && .is_string(target$layer) && .is_string(target$label) &&
        target$layer %in% names(rv$project$layers) &&
        target$label %in% rv$project$layers[[target$layer]]$labels &&
        !isTRUE(rv$project$layers[[target$layer]]$style$locked)
      if (!ok) {
        shiny::showNotification("Choose an unlocked layer and a label before drawing.", type = "warning")
        return(resend())
      }
      roi <- tryCatch(.feature_to_roi(event$payload, target$label), error = function(e) e)
      if (inherits(roi, "error")) {
        shiny::showNotification(paste("Could not add ROI:", .app_error_text(roi)), type = "warning")
        return(resend())
      }
      if (!.state_mutate(rv, function(p) at_add_roi(p, target$layer, roi), event, action = "draw")) resend()
    })

    shiny::observeEvent(input$canvas_erased, {
      event <- .state_event(rv, input$canvas_erased, widget = TRUE)
      shiny::req(event, rv$project, is.character(event$payload), length(event$payload) == 1L,
                 !is.na(event$payload))
      if (is.null(.find_roi(rv$project, event$payload))) return(resend())
      if (!.state_mutate(rv, function(p) at_remove_roi(p, event$payload), event, action = "erase")) resend()
    })

    shiny::observeEvent(input$canvas_edited, {
      event <- .state_event(rv, input$canvas_edited, widget = TRUE)
      shiny::req(event, rv$project, is.list(event$payload))
      ed <- event$payload
      shiny::req(ed$roi_id, ed$geometry)
      # Locate the existing object by its stable ID; do not recreate an ROI
      # (which would lose its ID, attributes, author and creation timestamp).
      rt <- at_rois(rv$project)
      row <- match(ed$roi_id, rt$roi_id)
      if (is.na(row)) return(resend())
      layer <- rt$layer[row]
      ids <- vapply(rv$project$layers[[layer]]$rois, `[[`, character(1), "id")
      index <- match(ed$roi_id, ids)
      original <- rv$project$layers[[layer]]$rois[[index]]
      roi <- tryCatch(at_transform(
        .feature_to_roi(list(type = "Feature", geometry = ed$geometry, properties = list()),
                        original$label),
        from_level = 0L, to_level = original$level, img = rv$project$image),
                      error = function(e) e)
      if (inherits(roi, "error")) {
        shiny::showNotification(paste("Edit failed:", .app_error_text(roi)), type = "warning")
        return(resend())
      }
      # A click without a drag reports the unchanged geometry: not an edit.
      if (isTRUE(all.equal(unname(sf::st_coordinates(roi$geometry)),
                           unname(sf::st_coordinates(original$geometry)),
                           tolerance = 1e-9, check.attributes = FALSE))) {
        return(invisible(NULL))
      }
      ok <- .state_mutate(rv, function(p) {
        original$geometry <- roi$geometry
        original$modified <- Sys.time()
        p$layers[[layer]]$rois[[index]] <- original
        p
      }, event, action = "edit")
      if (!ok) resend()
    })

    # Display-only events: probe, selection and viewport.
    shiny::observeEvent(input$canvas_probed, {
      p <- .state_view_payload(rv, input$canvas_probed)
      shiny::req(is.list(p), is.numeric(unlist(p$x)), is.numeric(unlist(p$y)))
      rv$probe <- c(x = as.numeric(p$x), y = as.numeric(p$y))
    })
    shiny::observeEvent(input$canvas_selected, {
      p <- .state_view_payload(rv, input$canvas_selected)
      rv$selection <- as.character(unlist(p))
    }, ignoreNULL = FALSE)
    shiny::observeEvent(input$canvas_viewport, {
      p <- .state_view_payload(rv, input$canvas_viewport)
      b <- unlist(p$bounds)
      if (length(b) == 4L) rv$viewport <- as.numeric(b)
    })

    shiny::observeEvent(rv$selection, {
      at_canvas_set_selection(proxy, as.character(rv$selection %||% character()))
    }, ignoreNULL = FALSE, ignoreInit = TRUE)
    shiny::observeEvent(rv$fit_bounds, {
      at_canvas_fit(proxy, rv$fit_bounds)
    }, ignoreInit = TRUE)
    shiny::observeEvent(list(rv$overlay_on, rv$project, rv$mask_type, rv$overlap), send_overlay(),
                        ignoreInit = TRUE)

    # Compatibility hook for standalone module callers; app keyboard actions
    # call the shared mutation synchronously with their original event stamp.
    shiny::observeEvent(rv$paste_forward, {
      event <- .state_event(rv, rv$paste_forward)
      previous <- .previous_project(rv)
      shiny::req(event, previous)
      .state_mutate(rv, function(p) .copy_forward(previous, p), event, action = "paste_forward")
    }, ignoreInit = TRUE)
  })
}

# ---- Mask -----------------------------------------------------------------------------

mod_mask_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Mask preview"),
    shiny::radioButtons(ns("type"), .sr_label("Mask type"),
                        choices = c("binary", "labelled", "multiclass"),
                        selected = "labelled", inline = TRUE),
    shiny::selectInput(ns("overlap"), "Overlap",
                       choices = c("last", "first", "max", "min")),
    shiny::checkboxInput(ns("overlay"), "Show mask overlay on the canvas", FALSE),
    shiny::plotOutput(ns("preview"), height = "200px"),
    shiny::uiOutput(ns("overlap_warn")),
    shiny::tableOutput(ns("stats")),
    shiny::actionButton(ns("export"), "Export this mask")
  )
}

# Build the current mask.
.current_mask <- function(rv) {
  shiny::req(rv$project)
  at_mask(rv$project, type = rv$mask_type %||% "labelled",
          overlap = rv$overlap %||% "last")
}

mod_mask_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    shiny::observeEvent(input$type, rv$mask_type <- input$type)
    shiny::observeEvent(input$overlap, rv$overlap <- input$overlap)
    shiny::observeEvent(input$overlay, rv$overlay_on <- isTRUE(input$overlay), ignoreInit = TRUE)
    output$preview <- shiny::renderPlot({
      if (is.null(rv$project)) {
        return(.message_plot(rv$display_error %||% "No image is open."))
      }
      if (nrow(at_rois(rv$project)) == 0L) {
        return(.message_plot("No ROIs yet \u2014 draw a region on the Annotate page."))
      }
      m <- tryCatch(.current_mask(rv), error = function(e) e)
      if (inherits(m, "error")) {
        return(.message_plot(paste("Mask unavailable:", .app_error_text(m))))
      }
      at_plot_mask(at_mask_preview(m, max_dim = 400L))
    })
    output$stats <- shiny::renderTable({
      m <- tryCatch(.current_mask(rv), error = function(e) NULL)
      if (is.null(m)) return(NULL)
      st <- at_mask_stats(m)
      st[, c("label", "n_px", "frac_total")]
    })
    output$overlap_warn <- shiny::renderUI({
      shiny::req(rv$project)
      ov <- at_rois_overlap(rv$project$layers[[rv$active_layer %||% names(rv$project$layers)[1]]],
                            image = rv$project$image)
      if (nrow(ov) > 0L) {
        shiny::span(class = "at-warn", "\u26a0 overlapping ROIs")
      }
    })
    shiny::observeEvent(input$export, {
      shiny::req(rv$project)
      dir <- file.path(rv$session$out_dir, "masks")
      path <- file.path(dir, paste0(.app_stems(rv$session)[rv$cursor], ".tif"))
      ok <- .app_try({
        if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
        at_write_mask(.current_mask(rv), path, overwrite = TRUE)
        TRUE
      }, "The mask export")
      if (isTRUE(ok)) shiny::showNotification(paste("Mask written to", path), type = "message")
    })
  })
}

# ---- ROI table ----------------------------------------------------------------------

mod_roitable_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("ROIs"),
    shiny::tableOutput(ns("table")),
    shiny::textInput(ns("del_id"), "ROI ID to delete or select", placeholder = "roi_id"),
    .at_action(ns("select"), "Select ROI", fields = list(del_id = ns("del_id"))),
    .at_action(ns("delete"), "Delete ROI", fields = list(del_id = ns("del_id")))
  )
}

mod_roitable_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    .state_init(rv)
    output$table <- shiny::renderTable({
      shiny::req(rv$project)
      rt <- at_rois(rv$project)
      if (nrow(rt) == 0L) {
        return(data.frame(roi_id = character(0), layer = character(0),
                          label = character(0), area_px = double(0), review = character(0)))
      }
      review <- vapply(rt$roi_id, function(id) {
        hit <- .find_roi(rv$project, id)
        hit$roi$attributes$review_status %||% "unreviewed"
      }, character(1))
      data.frame(roi_id = rt$roi_id, layer = rt$layer, label = rt$label,
                 area_px = round(rt$area_px, 1), review = unname(review))
    })
    shiny::observeEvent(input$delete, {
      event <- .state_event(rv, input$delete, fields = c("del_id"))
      shiny::req(event, rv$project, nzchar(event$payload$del_id))
      id <- trimws(event$payload$del_id)
      if (is.null(.find_roi(rv$project, id))) {
        shiny::showNotification(sprintf("No ROI %s in this image.", id), type = "warning")
        return()
      }
      .state_mutate(rv, function(p) at_remove_roi(p, id), event, action = "delete")
    })
    shiny::observeEvent(input$select, {
      event <- .state_event(rv, input$select, fields = c("del_id"))
      shiny::req(event, rv$project, nzchar(event$payload$del_id))
      rv$selection <- trimws(event$payload$del_id)
    })
  })
}

# ---- Export -------------------------------------------------------------------------

mod_export_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Export"),
    shiny::checkboxGroupInput(ns("formats"), "Formats",
                              choices = c("mask_tiff", "geojson", "qupath", "csv"),
                              selected = c("mask_tiff", "geojson")),
    shiny::selectInput(ns("scope"), "Scope",
                       choices = c("current", "complete", "all", "flagged")),
    shiny::downloadButton(ns("run"), "Export & download", class = "btn-primary"),
    shiny::helpText("Downloads a .zip; a copy is also written to the session's export folder."),
    shiny::textOutput(ns("outcome")),
    shiny::tableOutput(ns("receipt")),
    shiny::hr(),
    shiny::h5("qupflowR handoff"),
    shiny::helpText("Writes a neutral, SHA-256-inventoried handoff directory (QuPath GeoJSON,",
                    "masks with legends, manifest) under the session's export folder."),
    shiny::textInput(ns("handoff_name"), "Handoff folder name", placeholder = "handoff folder name"),
    shiny::actionButton(ns("handoff"), "Write handoff"),
    shiny::downloadButton(ns("handoff_zip"), "Download handoff (.zip)"),
    shiny::verbatimTextOutput(ns("handoff_status"))
  )
}

# Images to export for a given scope. The current image always uses the live
# (possibly unsaved) project; others use the project kept in the session.
.export_targets <- function(rv, scope) {
  st <- at_session_status(rv$session)
  switch(scope,
         current  = rv$cursor,
         complete = which(st$status == "complete"),
         flagged  = which(st$status == "flagged"),
         all      = seq_len(nrow(st)))
}

# Write the selected formats for every in-scope image into `dir` and return
# the receipt: one row per image and format with `entry_id`, `image`,
# `format`, `path`, `status` ("ok", "error" or "skipped"), `message` and
# `sidecar_path`, also written to `_export_manifest.csv`.
.write_exports <- function(rv, formats, scope, dir) {
  get_project <- function(i) if (i == rv$cursor) rv$project else rv$session$projects[[i]]
  rc <- .export_session_items(rv$session, .export_targets(rv, scope), dir, formats, get_project,
                              overwrite = TRUE, overlap = rv$overlap %||% "last",
                              flat = TRUE, skip_empty = TRUE)
  rc <- .export_receipt_files(rc, dir)
  attr(rc, "skipped") <- unique(rc$entry_id[rc$status == "skipped"])
  attr(rc, "failed") <- rc$message[rc$status == "error"]
  rc
}

# Zip `paths` (relative to `root`, keeping sub-directories) into `zipfile`.
.zip_into <- function(zipfile, paths, root) {
  root_n <- normalizePath(root, winslash = "/")
  files <- vapply(paths, function(p) .relative_to(p, root_n), character(1), USE.NAMES = FALSE)
  if (requireNamespace("zip", quietly = TRUE)) {
    zip::zip(zipfile = zipfile, files = files, root = root_n)
  } else {
    old <- setwd(root_n); on.exit(setwd(old))
    utils::zip(zipfile = zipfile, files = files, flags = "-q")
  }
}

# Zip a README explaining why a download could not produce its files (a
# failed download handler would give the browser no explanation).
.zip_note <- function(zipfile, title, text) {
  dir <- tempfile("hyperannotatR-note-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  note <- file.path(dir, "README.txt")
  writeLines(c(title, text), note)
  .zip_into(zipfile, note, dir)
}

mod_export_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    receipt <- shiny::reactiveVal(NULL)
    handoff <- shiny::reactiveVal(NULL)
    output$receipt <- shiny::renderTable({
      rc <- receipt()
      if (is.null(rc)) return(NULL)
      rc[, intersect(c("image", "format", "status", "path", "message"), names(rc)), drop = FALSE]
    })
    output$outcome <- shiny::renderText({
      rc <- receipt()
      if (is.null(rc)) return("")
      paste0(sum(rc$status == "ok"), " complete; ", sum(rc$status == "error"),
             " failed; ", sum(rc$status == "skipped"), " skipped.",
             if (!is.null(attr(rc, "receipt_error"))) paste0(" Receipt file failed: ", attr(rc, "receipt_error")))
    })

    output$run <- shiny::downloadHandler(
      filename = function() sprintf("hyperannotatR_export_%s.zip", input$scope %||% "current"),
      content = function(file) {
        dir <- file.path(rv$session$out_dir, "export")
        if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
        rc <- .app_try(.write_exports(rv, input$formats, input$scope %||% "current", dir), "The export")
        if (!is.data.frame(rc)) {
          receipt(NULL)
          return(.zip_note(file, "hyperannotatR export", "The export failed; see the notification in the app."))
        }
        receipt(rc)
        if (length(attr(rc, "failed"))) {
          shiny::showNotification(paste("Export failed for:", paste(attr(rc, "failed"), collapse = "; ")),
                                  type = "error")
        }
        ok <- rc$status == "ok"
        paths <- unique(c(rc$path[ok], rc$sidecar_path[ok]))
        paths <- paths[!is.na(paths) & file.exists(paths)]
        manifest <- file.path(dir, "_export_manifest.csv")
        if (is.null(attr(rc, "receipt_error")) && file.exists(manifest)) paths <- c(paths, manifest)
        if (!length(paths)) {
          return(.zip_note(file, "hyperannotatR export",
                           sprintf("Scope '%s' matched no annotated images to export.",
                                   input$scope %||% "current")))
        }
        .zip_into(file, paths, dir)
      }
    )

    write_handoff <- function() {
      shiny::req(rv$project)
      nm <- .safe_component(trimws(input$handoff_name %||% ""))
      if (identical(nm, "item")) nm <- paste0("handoff-", format(Sys.time(), "%Y%m%d-%H%M%S"))
      dest <- file.path(rv$session$out_dir, "handoff", nm)
      proj <- rv$project
      rc <- tryCatch(at_export_qupflowr(proj, dest, formats = c("qupath_geojson", "geojson",
                                                                "mask_tiff", "manifest"),
                                        overwrite = file.exists(file.path(dest, "integrity.json"))),
                     error = function(e) e)
      handoff(rc)
      rc
    }
    shiny::observeEvent(input$handoff, write_handoff())
    output$handoff_status <- shiny::renderText({
      rc <- handoff()
      if (is.null(rc)) return("No handoff written yet.")
      if (inherits(rc, "error")) return(paste("Handoff failed:", .app_error_text(rc)))
      sprintf("%s\n%d files, digest %s", basename(rc$destination), nrow(rc$files), rc$handoff_digest)
    })
    output$handoff_zip <- shiny::downloadHandler(
      filename = function() "hyperannotatR_qupflowr_handoff.zip",
      content = function(file) {
        rc <- write_handoff()
        if (inherits(rc, "error")) {
          shiny::showNotification(paste("Handoff failed:", .app_error_text(rc)), type = "error")
          return(.zip_note(file, "hyperannotatR qupflowR handoff",
                           paste("The handoff could not be written:", .app_error_text(rc))))
        }
        .zip_into(file, file.path(rc$destination, c(rc$files$path, "integrity.json")), rc$destination)
      }
    )
    receipt
  })
}

# ---- Session: save, status badge ----------------------------------------------------

mod_session_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    .at_action(ns("save"), "\U0001f4be Save"),
    .at_action(ns("complete"), "\u2713 Complete"),
    .at_action(ns("flag"), "\u2691 Flag"),
    shiny::uiOutput(ns("badge"), inline = TRUE),
    shiny::span(class = "at-saved", shiny::textOutput(ns("saved"), inline = TRUE))
  )
}

# Drop the bulky in-memory pixel handle before serialising: the image is
# re-opened from its source path on resume.
.lite_project <- function(p) {
  if (!is.null(p) && !is.null(p$image)) p$image$handle <- NULL
  p
}

# The annotation state shown to the user and reported to controllers.
.annotation_status <- function(rv) {
  if (isTRUE(rv$read_only)) return("read_only")
  if (!is.null(rv$staged)) return("staged")
  if (identical(rv$saved, "unavailable")) return("unavailable")
  if (identical(rv$saved, "unsaved")) return("unsaved")
  if (!is.null(rv$last_commit) && identical(rv$last_action, "commit")) return("committed")
  "saved"
}

mod_session_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    .state_init(rv)
    store <- shiny::isolate(rv$store)
    rv$save_callback <- function(candidate, cursor) {
      .app_backup_session(store, candidate)
      .app_save_checkpoint(candidate, cursor)
    }
    save_now <- function() .state_save(rv)
    shiny::observeEvent(input$save, {
      .state_save(rv, event = .state_event(rv, input$save))
    })
    shiny::observeEvent(rv$trigger_save, {
      .state_save(rv, event = .state_event(rv, rv$trigger_save))
    }, ignoreInit = TRUE)
    shiny::observeEvent(input$complete, {
      .state_save(rv, complete = TRUE, event = .state_event(rv, input$complete))
    })
    shiny::observeEvent(input$flag, {
      .state_status(rv, "flagged", .state_event(rv, input$flag))
    })
    # Mutations synchronously invoke autosave through the shared state helper.
    # No project/session observer retries a failed write without a new action.
    #
    # The badge is the one state indicator; next to it, when and where the
    # session was last checkpointed.
    output$badge <- shiny::renderUI({
      st <- .annotation_status(rv)
      label <- c(read_only = "read-only", staged = "staged", unavailable = "image unavailable",
                 unsaved = "unsaved", committed = "committed", saved = "saved")[[st]]
      n <- sum(vapply(rv$dirty, isTRUE, logical(1)))
      if (identical(st, "unsaved") && n > 1L) label <- sprintf("unsaved (%d images)", n)
      shiny::span(class = paste0("at-badge at-badge-", st), `data-state` = st,
                  role = "status", label)
    })
    output$saved <- shiny::renderText({
      od <- rv$session$out_dir
      # A reload or second tab continues a session another tab checkpointed:
      # fall back to the checkpoint file's time.
      saved_at <- rv$last_saved
      if (is.null(saved_at) && .is_string(od)) {
        f <- file.path(od, "_session.rds")
        if (file.exists(f)) saved_at <- file.mtime(f)
      }
      when <- if (is.null(saved_at)) "no checkpoint yet" else
        paste("checkpoint", format(saved_at, "%H:%M:%S"))
      where <- if (.app_is_temp(od)) "\u26a0 temporary folder" else basename(od)
      paste(when, "\u00b7", where)
    })
    list(save_now = save_now)
  })
}

# ---- Help -------------------------------------------------------------------------------

.shortcut_table <- function() {
  data.frame(
    key = c("Arrows / Shift+arrows", "Enter / Space", "Escape", "n / p", "N", "1-9",
            "q w e r t y", "d", "Ctrl+Z / Ctrl+Shift+Z", "Shift+Enter", "Shift+V", "f", "s",
            "Ctrl+E", "?"),
    action = c("canvas cursor: 1 / 10 image pixels",
               "point/rectangle anchors; polygon: Space vertices, Enter finish",
               "cancel unfinished drawing/edit", "next / previous image", "next pending image",
               "select label", "tool: pan/rect/polygon/freehand/circle/point", "delete last ROI",
               "undo / redo", "save, mark complete & advance",
               "paste previous image's ROIs", "flag image", "save session",
               "open export", "shortcut help"),
    stringsAsFactors = FALSE
  )
}

mod_help_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::actionButton(ns("show"), "? shortcuts", class = "w-100")
}

mod_help_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    output$shortcuts <- shiny::renderTable(.shortcut_table())
    show_help <- function() {
      shiny::showModal(shiny::modalDialog(
        title = "Keyboard shortcuts",
        shiny::tableOutput(session$ns("shortcuts")),
        easyClose = TRUE, footer = shiny::modalButton("Close")
      ))
    }
    shiny::observeEvent(input$show, show_help())
    shiny::observeEvent(rv$trigger_help, show_help(), ignoreInit = TRUE)
  })
}

# ---- Dashboard ------------------------------------------------------------------------------

# Whole-number axis breaks from zero.
.integer_breaks <- function(limits) {
  b <- pretty(c(0, max(1, limits[2], na.rm = TRUE)))
  b[b >= 0 & b == round(b)]
}

.metric_tile <- function(value, label) {
  shiny::div(class = "at-tile",
             shiny::div(class = "at-tile-val", value),
             shiny::div(class = "at-tile-lab", label))
}

mod_dashboard_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Progress"),
    shiny::uiOutput(ns("tiles")),
    shiny::br(),
    bslib::layout_columns(
      col_widths = c(7, 5),
      bslib::card(bslib::card_header("ROIs per image"),
                  shiny::plotOutput(ns("plot"), height = "300px")),
      bslib::card(bslib::card_header("Queue status"),
                  shiny::tableOutput(ns("status")))
    )
  )
}

mod_dashboard_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    status <- shiny::reactive({
      shiny::req(rv$session)
      rv$cursor
      rv$saved
      at_session_status(rv$session)
    })
    output$tiles <- shiny::renderUI({
      m <- status()
      shiny::div(
        class = "at-tiles",
        .metric_tile(nrow(m), "images"),
        .metric_tile(sum(m$status == "complete"), "complete"),
        .metric_tile(sum(m$status == "pending"), "pending"),
        .metric_tile(sum(m$status == "flagged"), "flagged"),
        .metric_tile(sum(m$n_rois), "ROIs total")
      )
    })
    output$status <- shiny::renderTable({
      m <- status()
      agg <- as.data.frame(table(factor(m$status,
        levels = c("pending", "in_progress", "complete", "flagged", "skipped"))))
      names(agg) <- c("status", "images")
      agg[agg$images > 0, , drop = FALSE]
    })
    output$plot <- shiny::renderPlot({
      m <- status()
      # Queue position keeps bars distinct when images share a name.
      lab <- sprintf("%d. %s", m$idx, m$name)
      df <- data.frame(image = factor(lab, levels = lab),
                       n = m$n_rois, status = m$status)
      ggplot2::ggplot(df, ggplot2::aes(x = .data$image, y = .data$n, fill = .data$status)) +
        ggplot2::geom_col() +
        ggplot2::scale_fill_manual(values = c(
          pending = "#7f93a8", in_progress = "#e3a008", complete = "#1f6feb",
          flagged = "#d55e00", skipped = "#495867"), drop = FALSE) +
        # Counts start at zero with whole-number breaks, even for an empty queue.
        ggplot2::scale_y_continuous(breaks = .integer_breaks,
                                    expand = ggplot2::expansion(mult = c(0, 0.05))) +
        ggplot2::expand_limits(y = c(0, 1)) +
        ggplot2::labs(x = NULL, y = "ROIs", fill = NULL) +
        ggplot2::coord_flip() +
        ggplot2::theme_minimal(base_size = 12)
    })
  })
}

# ---- Data -----------------------------------------------------------------------------------

mod_data_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Data source"),
    shiny::helpText("Paths are read on the machine running R. Set",
                    shiny::code("options(hyperannotatR.app_root = )"),
                    "to restrict them to one folder; the app is meant for local use."),
    bslib::layout_columns(
      col_widths = c(9, 3),
      shiny::textInput(ns("dir"), "Image folder", placeholder = "/path/to/a/folder of images or cubes"),
      .at_action(ns("load"), "Load folder", class = "btn-primary", fields = list(dir = ns("dir")))
    ),
    shiny::div(class = "at-progress", role = "status", shiny::textOutput(ns("msg"), inline = TRUE)),
    .at_action(ns("restore"), "Restore previous queue"),
    shiny::textOutput(ns("recovery")),
    shiny::h5("Import reviewed annotations (qupflowR handoff)"),
    bslib::layout_columns(
      col_widths = c(9, 3),
      shiny::textInput(ns("handoff"), "Handoff directory or QuPath GeoJSON",
                       placeholder = "/path/to/handoff directory or QuPath GeoJSON"),
      .at_action(ns("stage"), "Stage import", fields = list(handoff = ns("handoff")))
    ),
    shiny::div(class = "at-progress", role = "status", shiny::textOutput(ns("stage_msg"), inline = TRUE)),
    shiny::h5("Current queue"),
    shiny::tableOutput(ns("table"))
  )
}

# A new queue's checkpoint folder inside the current one, so loading another
# folder never overwrites the previous queue's checkpoint.
.state_session_dir <- function(rv) {
  file.path(rv$session$out_dir, .new_identity_id("session"))
}

mod_data_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    .state_init(rv)
    msg <- shiny::reactiveVal("")
    stage_msg <- shiny::reactiveVal("")

    shiny::observeEvent(input$load, {
      event <- .state_event(rv, input$load, fields = c("dir"))
      shiny::req(event)
      if (isTRUE(rv$controlled)) {
        msg("A control service drives this queue; load images with its session.load command.")
        return()
      }
      d <- trimws(event$payload$dir)
      if (!nzchar(d) || !dir.exists(d)) {
        msg("Folder not found."); return()
      }
      if (!.app_path_allowed(d)) {
        msg("That folder is outside the folder this app may read (option hyperannotatR.app_root)."); return()
      }
      files <- .app_list_images(d)
      if (!length(files)) {
        msg("No supported images found in that folder."); return()
      }
      new_sess <- tryCatch(
        at_session(as.character(files), labels = rv$session$labels,
                   layers = rv$session$layer_spec, out_dir = .state_session_dir(rv),
                   autosave = rv$session$autosave),
        error = function(e) e)
      if (inherits(new_sess, "error")) {
        msg(paste("Load failed:", .app_error_text(new_sess))); return()
      }
      if (.state_replace(rv, new_sess, event)) {
        msg(sprintf("Loaded %d image(s)%s. Previous queue retained; use Restore previous queue to recover its annotations.",
                    nrow(new_sess$manifest),
                    if (isTRUE(attr(files, "truncated"))) " (listing truncated)" else ""))
      }
    })

    shiny::observeEvent(input$restore, {
      if (.state_restore_queue(rv, .state_event(rv, input$restore))) {
        msg("Previous queue restored with its annotations and save state.")
      }
    })
    output$recovery <- shiny::renderText({
      if (!is.null(rv$recovery_queue)) "Previous queue and any unsaved annotations are retained in this session. Restore them before closing the app."
      else "No previous queue is retained."
    })
    output$msg <- shiny::renderText(msg())

    shiny::observeEvent(input$stage, {
      event <- .state_event(rv, input$stage, fields = c("handoff"))
      shiny::req(event, rv$project)
      path <- trimws(event$payload$handoff)
      if (!nzchar(path) || !file.exists(path)) {
        stage_msg("Handoff not found."); return()
      }
      if (!.app_path_allowed(path)) {
        stage_msg("That path is outside the folder this app may read (option hyperannotatR.app_root)."); return()
      }
      res <- tryCatch({
        rep <- at_import_qupflowr(path)
        at_stage_qupflowr(rv$project, rep)
      }, error = function(e) e)
      if (inherits(res, "error")) {
        stage_msg(paste("Import refused:", .app_error_text(res))); return()
      }
      rv$staged <- res
      s <- res$summary
      stage_msg(sprintf("Staged: %d create, %d update, %d conflict. Review it on the Annotate page.",
                        s$create, s$update, s$conflict))
    })
    output$stage_msg <- shiny::renderText(stage_msg())

    output$table <- shiny::renderTable({
      shiny::req(rv$session)
      rv$cursor
      m <- at_session_status(rv$session)
      data.frame(idx = m$idx, name = m$name, status = m$status,
                 n_rois = m$n_rois, path = m$path)
    })
  })
}
