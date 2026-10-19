# Hyperspectral panels of the annotation app: band / pseudo-RGB / band-operation
# display, cube and calibration status, spectral curves for a pixel, an ROI or a
# layer, and bounded download of raw region values. Display products never
# replace the cube values used by masks, spectra or exports. Internal.

# Band choices "index: name (wavelength unit)" for select inputs.
.band_choices <- function(img) {
  b <- at_bands(img)
  lab <- ifelse(is.na(b$wavelength), sprintf("%d: %s", b$index, b$name),
                sprintf("%d: %s (%g %s)", b$index, b$name, b$wavelength, b$unit))
  stats::setNames(as.character(b$index), lab)
}

mod_view_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Display"),
    shiny::selectInput(ns("mode"), .sr_label("Display mode"), choices = c(
      "Natural colour" = "natural", "Single band" = "single", "Pseudo-RGB / false colour" = "rgb",
      "Band ratio" = "ratio", "Normalised difference" = "normalized_difference",
      "Mean of bands" = "band_mean", "Wavelength window mean" = "wavelength_window_mean"
    )),
    shiny::uiOutput(ns("band_inputs")),
    shiny::actionButton(ns("apply"), "Apply display"),
    shiny::div(class = "at-progress", role = "note",
               "Display only: masks, spectra and exports use the original values."),
    shiny::h5("Cube"),
    shiny::tableOutput(ns("status"))
  )
}

# The live image as a reactive that changes only when the image does, not on
# every annotation edit (reactiveVal ignores identical values), so controls
# built from it keep the user's choices while they draw.
.image_reactive <- function(rv) {
  img <- shiny::reactiveVal(NULL)
  shiny::observe({
    p <- rv$project
    img(if (is.null(p)) NULL else p$image)
  })
  img
}

# Keep a still-valid previous choice of a select input, else the default.
.keep_choice <- function(previous, choices, default) {
  prev <- previous[previous %in% choices]
  if (length(prev)) prev else default
}

mod_view_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    image <- .image_reactive(rv)
    output$band_inputs <- shiny::renderUI({
      img <- image()
      shiny::req(img)
      ch <- .band_choices(img)
      ns <- session$ns
      mode <- input$mode %||% "natural"
      def <- as.character(.default_rgb_bands(img, img$n_bands))
      keep <- function(id, default) .keep_choice(shiny::isolate(input[[id]]), ch, default)
      switch(
        mode,
        natural = NULL,
        single = shiny::selectInput(ns("b1"), "Band", ch, selected = keep("b1", ch[1])),
        rgb = shiny::tagList(
          shiny::selectInput(ns("b1"), "Red", ch, selected = keep("b1", def[1])),
          shiny::selectInput(ns("b2"), "Green", ch, selected = keep("b2", def[2])),
          shiny::selectInput(ns("b3"), "Blue", ch, selected = keep("b3", def[3]))
        ),
        ratio = , normalized_difference = shiny::tagList(
          shiny::selectInput(ns("b1"), "Band a", ch, selected = keep("b1", ch[1])),
          shiny::selectInput(ns("b2"), "Band b", ch, selected = keep("b2", ch[min(2L, length(ch))]))
        ),
        band_mean = shiny::selectInput(ns("bands"), "Bands", ch, multiple = TRUE,
                                       selected = keep("bands", ch[1])),
        wavelength_window_mean = {
          wl <- at_wavelengths(img)
          if (!length(wl) || all(is.na(wl))) {
            shiny::div(class = "at-warn", "This image has no wavelengths.")
          } else {
            shiny::tagList(
              shiny::numericInput(ns("wmin"), "From (nm)", value = min(wl, na.rm = TRUE)),
              shiny::numericInput(ns("wmax"), "To (nm)", value = max(wl, na.rm = TRUE))
            )
          }
        }
      )
    })
    shiny::observeEvent(input$apply, {
      shiny::req(rv$project)
      img <- rv$project$image
      mode <- input$mode %||% "natural"
      view <- switch(
        mode,
        natural = NULL,
        single = list(operation = "single", bands = as.integer(input$b1)),
        rgb = list(operation = "rgb", bands = as.integer(c(input$b1, input$b2, input$b3))),
        ratio = , normalized_difference = list(operation = mode,
                                               bands = as.integer(c(input$b1, input$b2))),
        band_mean = list(operation = "band_mean", bands = as.integer(input$bands)),
        wavelength_window_mean = list(operation = "wavelength_window_mean",
                                      params = list(wavelength_min = input$wmin,
                                                    wavelength_max = input$wmax))
      )
      ok <- if (is.null(view)) TRUE else tryCatch({
        .check_band_view(img, view$operation, view$bands, view$params %||% list())
        TRUE
      }, error = function(e) {
        shiny::showNotification(.app_error_text(e), type = "warning")
        FALSE
      })
      if (ok) rv$view <- view
    })
    output$status <- shiny::renderTable({
      img <- image()
      shiny::req(img)
      # Read counters change when the canvas or a spectrum reads pixels, which
      # happens outside this output's dependencies: refresh them periodically.
      shiny::invalidateLater(2000)
      hm <- at_hsi_meta(img)
      rs <- at_read_stats(img)
      bands <- at_bands(img)
      gaps <- sum(bands$wavelength_status != "ok")
      data.frame(
        field = c("kind", "size", "bands", "wavelengths", "value unit", "calibration",
                  "pyramid levels", "plane (c, z, t)", "window reads", "bytes read so far",
                  "display", "coordinates"),
        value = c(
          hm$image_kind, sprintf("%d x %d px", hm$width, hm$height), as.character(hm$n_bands),
          if (hm$image_kind == "spectral") sprintf("%g-%g %s, %d gap(s)",
                                                   min(bands$wavelength, na.rm = TRUE),
                                                   max(bands$wavelength, na.rm = TRUE),
                                                   hm$wavelength_unit, gaps) else "none",
          hm$value_unit, hm$calibration$status %||% "missing",
          as.character(hm$n_levels),
          sprintf("%s, %s, %s", ifelse(is.na(hm$plane$c), "all", hm$plane$c), hm$plane$z, hm$plane$t),
          if (isTRUE(hm$window_read)) "yes" else "no (in memory)",
          format(rs$file_bytes, big.mark = ","),
          (rv$view$operation %||% "natural colour"),
          "origin top-left, y down, px"
        )
      )
    })
  })
}

# ---- Spectra ------------------------------------------------------------------------

mod_spectrum_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::uiOutput(ns("panel"))
}

# Spectrum of one pixel (1-based pixel containing the level-0 point).
.pixel_spectrum <- function(img, x, y) {
  d <- at_dims(img)
  col <- as.integer(floor(x)) + 1L
  row <- as.integer(floor(y)) + 1L
  if (col < 1L || row < 1L || col > d[1] || row > d[2]) {
    return(NULL)
  }
  v <- at_tile(img, xrange = c(col, col), yrange = c(row, row))
  b <- at_bands(img)
  tibble::tibble(roi_id = sprintf("pixel(%d,%d)", col, row), layer = NA_character_,
                 label = "pixel", band = b$index, band_name = b$name,
                 wavelength = b$wavelength, unit = b$unit, stat = "value", value = as.numeric(v),
                 n_px = 1L)
}

mod_spectrum_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    image <- .image_reactive(rv)
    is_spectral <- shiny::reactive({
      shiny::req(image())
      at_is_spectral(image())
    })
    output$panel <- shiny::renderUI({
      if (!is_spectral()) {
        return(shiny::div(class = "at-progress at-hint",
                          "Spectra are shown for spectral images (cubes with wavelengths)."))
      }
      ns <- session$ns
      shiny::tagList(
        shiny::h5("Spectra"),
        shiny::radioButtons(ns("source"), NULL, inline = TRUE,
                            choices = c("all ROIs" = "all", "layer" = "layer", "ROI" = "roi",
                                        "probed pixel" = "pixel")),
        shiny::uiOutput(ns("source_sel")),
        shiny::plotOutput(ns("plot"), height = "220px"),
        shiny::div(class = "at-progress", shiny::textOutput(ns("caption"), inline = TRUE))
      )
    })
    output$source_sel <- shiny::renderUI({
      shiny::req(rv$project)
      ns <- session$ns
      # Re-rendered after edits; keep the user's layer or ROI while it exists.
      switch(input$source %||% "all",
             layer = {
               ch <- names(rv$project$layers)
               shiny::selectInput(ns("layer"), .sr_label("Layer"), ch,
                                  selected = .keep_choice(shiny::isolate(input$layer), ch, ch[1]))
             },
             roi = {
               ch <- at_rois(rv$project)$roi_id
               if (!length(ch)) return(shiny::div(class = "at-progress", "No ROIs yet."))
               shiny::selectInput(ns("roi"), .sr_label("ROI"), ch,
                                  selected = .keep_choice(shiny::isolate(input$roi), ch, ch[1]))
             },
             NULL)
    })
    spectra <- shiny::reactive({
      shiny::req(rv$project, is_spectral())
      img <- rv$project$image
      src <- input$source %||% "all"
      switch(
        src,
        pixel = {
          shiny::req(rv$probe)
          .pixel_spectrum(img, rv$probe[["x"]], rv$probe[["y"]])
        },
        layer = {
          shiny::req(input$layer)
          at_extract_spectrum(rv$project, layer = input$layer)
        },
        roi = {
          shiny::req(input$roi)
          hit <- .find_roi(rv$project, input$roi)
          shiny::req(hit)
          one <- at_project(img, at_layer_add(at_layer(hit$layer), hit$roi))
          at_extract_spectrum(one)
        },
        at_extract_spectrum(rv$project)
      )
    })
    output$plot <- shiny::renderPlot({
      sp <- tryCatch(spectra(), error = function(e) {
        if (inherits(e, "shiny.silent.error")) NULL else e
      })
      if (inherits(sp, "error")) {
        return(.message_plot(paste("Spectrum unavailable:", .app_error_text(sp))))
      }
      if (is.null(sp) || nrow(sp) == 0L) {
        return(.message_plot("Draw a region or probe a pixel to see spectra."))
      }
      at_plot_spectrum(sp)
    })
    output$caption <- shiny::renderText({
      shiny::req(rv$project, is_spectral())
      hm <- at_hsi_meta(rv$project$image)
      gaps <- sum(at_bands(rv$project$image)$wavelength_status != "ok")
      sprintf("values: %s | calibration: %s | wavelength gaps: %d | source: original cube",
              hm$value_unit, hm$calibration$status %||% "missing", gaps)
    })
    is_spectral
  })
}

# ---- Region download ------------------------------------------------------------------

# Write a float64 BSQ ENVI cube (raw values) with its header.
.write_envi_cube <- function(arr, path, wavelengths = NULL, band_names = NULL,
                             description = "hyperannotatR region export") {
  d <- dim(arr)
  con <- file(path, "wb")
  writeBin(as.double(aperm(arr, c(2, 1, 3))), con, size = 8L, endian = "little")
  close(con)
  hdr <- c(
    "ENVI",
    sprintf("description = {%s}", description),
    sprintf("samples = %d", d[2]), sprintf("lines = %d", d[1]), sprintf("bands = %d", d[3]),
    "header offset = 0", "file type = ENVI Standard", "data type = 5",
    "interleave = bsq", "byte order = 0"
  )
  if (length(wavelengths) == d[3] && !anyNA(wavelengths)) {
    hdr <- c(hdr, "wavelength units = Nanometers",
             sprintf("wavelength = {%s}", paste(format(wavelengths, digits = 15), collapse = ", ")))
  }
  if (length(band_names) == d[3]) {
    hdr <- c(hdr, sprintf("band names = {%s}", paste(gsub("[{},]", "_", band_names), collapse = ", ")))
  }
  writeLines(hdr, sub("\\.dat$", ".hdr", path))
  invisible(path)
}

# Write raw values of a region plus provenance into `dir`; returns file paths.
.write_region <- function(img, xrange, yrange, bands, dir) {
  n <- (diff(xrange) + 1) * (diff(yrange) + 1)
  if (n > .interop_limits()$region_download_max_pixels) {
    .at_abort("The region has {n} pixels, over the download limit.", class = "limit",
              code = "PAYLOAD_TOO_LARGE")
  }
  arr <- at_tile(img, xrange = xrange, yrange = yrange, bands = bands)
  b <- at_bands(img)[bands, ]
  dat <- file.path(dir, "region.dat")
  .write_envi_cube(arr, dat, wavelengths = b$wavelength, band_names = b$name)
  meta <- list(
    document = "annotatr_region",
    parent_image = .image_record(img, hash = FALSE)[c("source_name", "backend", "width", "height",
                                                       "n_bands", "dtype", "transform_digest")],
    parent_digest = .image_identity_digest(img),
    bounds = list(xmin = xrange[1] - 1L, ymin = yrange[1] - 1L, xmax = xrange[2], ymax = yrange[2]),
    level = 0L,
    bands = lapply(seq_len(nrow(b)), function(i) list(index = b$index[i], name = b$name[i],
                                                      wavelength = b$wavelength[i], unit = b$unit[i])),
    value_unit = at_hsi_meta(img)$value_unit,
    display_product = FALSE,
    note = "Raw values in [y, x, band] order written as a float64 BSQ ENVI cube."
  )
  .write_json_atomic(meta, file.path(dir, "region.json"))
  c(dat, file.path(dir, "region.hdr"), file.path(dir, "region.json"))
}

mod_region_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Download region"),
    shiny::radioButtons(ns("extent"), NULL, inline = TRUE,
                        choices = c("selected ROI bbox" = "roi", "current view" = "view",
                                    "custom" = "custom")),
    shiny::uiOutput(ns("custom")),
    shiny::downloadButton(ns("download"), "Download raw values (.zip)")
  )
}

mod_region_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    output$custom <- shiny::renderUI({
      if (!identical(input$extent, "custom")) return(NULL)
      ns <- session$ns
      shiny::tagList(
        shiny::numericInput(ns("xmin"), "x min (px)", 0), shiny::numericInput(ns("ymin"), "y min (px)", 0),
        shiny::numericInput(ns("xmax"), "x max (px)", 64), shiny::numericInput(ns("ymax"), "y max (px)", 64)
      )
    })
    bounds <- function() {
      img <- rv$project$image
      d <- at_dims(img)
      bb <- switch(
        input$extent %||% "roi",
        roi = {
          sel <- rv$selection
          hit <- if (length(sel)) .find_roi(rv$project, sel[1]) else NULL
          if (is.null(hit)) NULL else at_roi_bbox(hit$roi)
        },
        view = rv$viewport,
        custom = c(input$xmin, input$ymin, input$xmax, input$ymax)
      )
      if (is.null(bb) || length(bb) != 4L || anyNA(bb)) {
        .at_abort("Select an ROI, pan the view, or enter custom bounds first.", code = "VALIDATION_FAILED")
      }
      xr <- c(max(1L, as.integer(floor(bb[1])) + 1L), min(d[1], as.integer(ceiling(bb[3]))))
      yr <- c(max(1L, as.integer(floor(bb[2])) + 1L), min(d[2], as.integer(ceiling(bb[4]))))
      if (xr[1] > xr[2] || yr[1] > yr[2]) {
        .at_abort("The region lies outside the image.", code = "VALIDATION_FAILED")
      }
      list(x = xr, y = yr)
    }
    output$download <- shiny::downloadHandler(
      filename = function() "hyperannotatR_region.zip",
      content = function(file) {
        shiny::req(rv$project)
        img <- rv$project$image
        dir <- tempfile("hyperannotatR-region-")
        dir.create(dir)
        on.exit(unlink(dir, recursive = TRUE), add = TRUE)
        paths <- tryCatch({
          b <- bounds()
          .write_region(img, b$x, b$y, seq_len(img$n_bands), dir)
        }, error = function(e) {
          # A failed download carries no explanation: ship the reason instead.
          shiny::showNotification(paste("Region download failed:", .app_error_text(e)),
                                  type = "error")
          note <- file.path(dir, "README.txt")
          writeLines(c("hyperannotatR region download",
                       paste("No region was written:", .app_error_text(e))), note)
          note
        })
        .zip_into(file, paths, dir)
      }
    )
  })
}

# ---- Staged partner patches ------------------------------------------------------------

mod_staging_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::uiOutput(ns("panel"))
}

mod_staging_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    output$panel <- shiny::renderUI({
      st <- rv$staged
      if (is.null(st)) return(NULL)
      ns <- session$ns
      bslib::card(
        class = "at-staged",
        bslib::card_header("Staged changes"),
        shiny::tableOutput(ns("ops")),
        shiny::div(
          .at_action(ns("commit"), "Commit staged changes", class = "btn-primary"),
          .at_action(ns("discard"), "Discard")
        )
      )
    })
    output$ops <- shiny::renderTable({
      st <- rv$staged
      shiny::req(st)
      as.data.frame(st$operations[st$operations$op != "unchanged", ])
    })
    shiny::observeEvent(input$commit, {
      event <- .state_event(rv, input$commit)
      st <- rv$staged
      shiny::req(event, st, rv$project)
      if (isTRUE(rv$read_only)) {
        shiny::showNotification("Read-only session: commit refused.", type = "warning")
        return()
      }
      current <- at_annotation_revision(rv$project)
      if (!identical(current, st$base_revision)) {
        shiny::showNotification("The image changed since staging; stage the import again.",
                                type = "error")
        return()
      }
      rc <- tryCatch(at_commit_qupflowr(st), error = function(e) e)
      if (inherits(rc, "error")) {
        shiny::showNotification(paste("Commit failed:", .app_error_text(rc)), type = "error")
        return()
      }
      rv$last_commit <- rc
      # The committed layers replace the live ones through the shared
      # transition (history, protection, identity); the entry keeps its meta.
      committed <- .state_mutate(rv, function(p) {
        q <- rc$project
        q$meta <- p$meta
        q
      }, event, action = "commit")
      if (!isTRUE(committed)) return()
      rv$staged <- NULL
      # A commit is persisted at once, with or without autosave.
      if (identical(rv$saved, "unsaved")) .state_save(rv)
    })
    shiny::observeEvent(input$discard, {
      shiny::req(.state_event(rv, input$discard))
      rv$staged <- NULL
    })
  })
}
