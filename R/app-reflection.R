# Conservative seed-based proposals from the displayed RGB image. The result
# remains a preview until an identity-checked, explicit acceptance action.
.reflection_membership <- function(rgb, x, y, tolerance = 0.1) {
  d <- dim(rgb)
  if (length(d) != 3L || d[3] != 3L || any(!is.finite(rgb)) ||
      any(rgb < 0 | rgb > 1)) {
    .at_abort("Reflection detection needs a finite RGB display in [0, 1].",
              class = "validation", code = "REFLECTION_RGB")
  }
  if (!is.numeric(x) || !is.numeric(y) || length(x) != 1L || length(y) != 1L ||
      !is.finite(x) || !is.finite(y) || x < 0 || y < 0 || x >= d[2] || y >= d[1]) {
    .at_abort("Click inside the image.", class = "validation", code = "REFLECTION_SEED")
  }
  .check_number(tolerance, min = 0, max = 0.25)
  row <- as.integer(floor(y)) + 1L
  col <- as.integer(floor(x)) + 1L
  low <- pmin(rgb[, , 1], rgb[, , 2], rgb[, , 3])
  high <- pmax(rgb[, , 1], rgb[, , 2], rgb[, , 3])
  seed <- low[row, col]
  if (seed < 0.7 || high[row, col] - seed > 0.3) {
    .at_abort("Choose a bright, near-white reflection, or draw it manually.",
              class = "validation", code = "REFLECTION_NOT_BRIGHT")
  }
  eligible <- low >= max(0.7, seed - tolerance) &
    high - low <= max(0.25, high[row, col] - seed + 0.1)
  # Four neighbours prevent growth across a single diagonal touching pixel.
  limit <- max(64L, as.integer(ceiling(0.05 * prod(d[1:2]))))
  queue <- integer(limit)
  seen <- matrix(FALSE, d[1], d[2])
  queue[1] <- row + (col - 1L) * d[1]
  seen[queue[1]] <- TRUE
  head <- 1L
  tail <- 1L
  while (head <= tail) {
    index <- queue[head]
    head <- head + 1L
    r <- (index - 1L) %% d[1] + 1L
    c <- (index - 1L) %/% d[1] + 1L
    neighbours <- c(if (r > 1L) index - 1L, if (r < d[1]) index + 1L,
                    if (c > 1L) index - d[1], if (c < d[2]) index + d[1])
    for (j in neighbours) {
      if (seen[j] || !eligible[j]) next
      if (tail >= limit) {
        .at_abort("The bright region is too broad. Try Tight extent or draw manually.",
                  class = "limit", code = "REFLECTION_TOO_BROAD")
      }
      tail <- tail + 1L
      queue[tail] <- j
      seen[j] <- TRUE
    }
  }
  seen
}

.reflection_roi <- function(member, label) {
  height <- nrow(member)
  width <- ncol(member)
  bb <- sf::st_bbox(c(xmin = 0, ymin = 0, xmax = width, ymax = height))
  raster <- stars::st_as_stars(bb, nx = as.integer(width),
                              ny = as.integer(height), values = 0L)
  raster[[1]][] <- t(member[height:1, , drop = FALSE])
  regions <- suppressWarnings(sf::st_as_sf(raster, as_points = FALSE,
    merge = TRUE, connect8 = FALSE, use_integer = FALSE))
  regions <- regions[regions[[1]] != 0, , drop = FALSE]
  geometry <- sf::st_union(sf::st_geometry(regions))
  at_roi_from_sf(geometry, label = label, source = "assisted",
                 method = "rgb-bright-connected-v1", reviewed = FALSE)
}

.reflection_preview_valid <- function(rv) {
  p <- rv$reflection_preview
  !is.null(p) && !isTRUE(rv$read_only) && identical(rv$tool, "reflection") &&
    .state_matches(rv, p$stamp) && identical(p$layer, rv$active_layer) &&
    identical(p$roi$label, rv$active_label) && identical(p$view, rv$view) &&
    !isTRUE(rv$project$layers[[p$layer]]$style$locked)
}

.reflection_preview_feature <- function(rv) {
  if (!.reflection_preview_valid(rv)) return(NULL)
  p <- rv$reflection_preview
  .roi_to_feature(p$roi, p$layer, p$roi$geometry[[1]])
}

.reflection_server <- function(input, output, session, rv) {
  shiny::observe({
    if (!is.null(rv$reflection_preview) && !.reflection_preview_valid(rv))
      rv$reflection_preview <- NULL
  })
  shiny::observeEvent(input$reflection_tolerance, {
    if (input$reflection_tolerance %in% c("0.04", "0.1", "0.18")) {
      rv$reflection_tolerance <- as.numeric(input$reflection_tolerance)
      rv$reflection_preview <- NULL
    }
  })
  shiny::observeEvent(input$canvas_reflection_seed, {
    event <- .state_event(rv, input$canvas_reflection_seed, widget = TRUE)
    shiny::req(event, rv$project, !isTRUE(rv$read_only),
               identical(rv$tool, "reflection"), is.list(event$payload))
    rv$reflection_preview <- NULL
    target <- event$payload$target
    valid <- is.list(target) && .is_string(target$label) &&
      .is_string(target$layer) && identical(target$layer, rv$active_layer) &&
      identical(target$label, rv$active_label) &&
      target$label %in% rv$project$layers[[target$layer]]$labels &&
      !isTRUE(rv$project$layers[[target$layer]]$style$locked)
    if (!valid || !grepl("^reflect(ions|ations)$", target$label, ignore.case = TRUE)) {
      shiny::showNotification("Select the reflections label in your artifacts layer first.",
                              type = "warning")
      return()
    }
    .app_try({
      dims <- at_dims(rv$project$image)
      if (max(dims) > 2048L) {
        .at_abort("The reflection wand supports displays up to 2048 pixels per side.",
                  class = "limit", code = "REFLECTION_DISPLAY_SIZE")
      }
      rgb <- .view_display_array(rv$project$image, rv$view, max_dim = 2048L)
      if (!identical(as.integer(dim(rgb)[2:1]), as.integer(dims))) {
        .at_abort("Reflection detection requires the original pixel grid.",
                  class = "validation", code = "REFLECTION_GRID")
      }
      tolerance <- rv$reflection_tolerance %||% 0.1
      member <- .reflection_membership(rgb, event$payload$x, event$payload$y, tolerance)
      roi <- .reflection_roi(member, target$label)
      roi$attributes$seed <- c(event$payload$x, event$payload$y)
      roi$attributes$tolerance <- tolerance
      rv$reflection_preview <- list(roi = roi, layer = target$layer,
        stamp = .state_stamp(rv), view = rv$view, pixels = sum(member))
    }, "Reflection proposal")
  })
  output$reflection_review <- shiny::renderUI({
    if (!.reflection_preview_valid(rv)) return(NULL)
    p <- rv$reflection_preview
    shiny::tagList(
      shiny::p(paste(p$pixels, "pixels proposed; not saved yet.")),
      shiny::tags$input(type = "hidden", id = session$ns("reflection_id"), value = p$roi$id),
      shiny::div(class = "at-toolbar",
        .at_action(session$ns("accept_reflection"), "Accept reflection",
          fields = list(preview_id = session$ns("reflection_id"))),
        .at_action(session$ns("discard_reflection"), "Discard",
          fields = list(preview_id = session$ns("reflection_id")))))
  })
  shiny::observeEvent(input$accept_reflection, {
    event <- .state_event(rv, input$accept_reflection)
    shiny::req(event, .reflection_preview_valid(rv))
    p <- rv$reflection_preview
    shiny::req(identical(event$payload$preview_id, p$roi$id))
    p$roi$attributes$reviewed <- TRUE
    p$roi$modified <- Sys.time()
    ok <- .state_mutate(rv, function(project) at_add_roi(project, p$layer, p$roi),
                        event, action = "draw")
    if (isTRUE(ok)) rv$reflection_preview <- NULL
  })
  shiny::observeEvent(input$discard_reflection, {
    event <- .state_event(rv, input$discard_reflection)
    shiny::req(event, !is.null(rv$reflection_preview),
      identical(event$payload$preview_id, rv$reflection_preview$roi$id))
    rv$reflection_preview <- NULL
  })
}
