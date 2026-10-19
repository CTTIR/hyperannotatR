# Visualisation. Every function returns a ggplot2 object and never draws; print
# the returned object to render. Conventions: theme_minimal base, Okabe-Ito
# discrete palette, viridis continuous, full axis/title labels, and image
# orientation (y down) in level-0 pixel coordinates: raster layers use
# coord_fixed + scale_y_reverse, sf layers coord_sf with a reversed y axis.

# Choose the finest pyramid level whose largest dimension is <= max_dim, so the
# display keeps as much detail as the budget allows; when no level fits, the
# coarsest one, which needs the least downsampling.
.display_level <- function(img, max_dim) {
  for (l in seq_len(img$n_levels) - 1L) {
    d <- img$level_dims[[l + 1L]]
    if (max(d) <= max_dim) {
      return(l)
    }
  }
  img$n_levels - 1L
}

# A y-down coordinate system for sf layers. geom_sf ignores scale_y_reverse(),
# which would draw ROIs mirrored against the image; ggplot2 >= 4.0 reverses the
# axis in coord_sf itself. Older versions flip the drawn geometry instead and
# relabel the axis, leaving the plot data in image coordinates.
.coord_sf_reverse_y <- function() {
  "reverse" %in% names(formals(ggplot2::coord_sf))
}

.sf_image_coord <- function() {
  if (.coord_sf_reverse_y()) {
    return(ggplot2::coord_sf(reverse = "y", default_crs = NULL))
  }
  list(ggplot2::coord_sf(default_crs = NULL),
       ggplot2::scale_y_continuous(labels = function(b) -b))
}

# The geometry to draw for sf layers: unchanged where coord_sf reverses the
# axis, mirrored (y -> -y) otherwise.
.sf_display_data <- function(sfp) {
  if (.coord_sf_reverse_y() || nrow(sfp) == 0L) {
    return(sfp)
  }
  sf::st_geometry(sfp) <- sf::st_geometry(sfp) * matrix(c(1, 0, 0, -1), 2, 2)
  sfp
}

# Map an rgb argument (band indices, or wavelengths in nm) to band indices.
.resolve_rgb <- function(img, rgb) {
  if (is.null(rgb)) {
    return(NULL)
  }
  rgb <- as.numeric(rgb)
  if (at_is_spectral(img) && any(rgb > img$n_bands)) {
    wl <- at_wavelengths(img)
    return(vapply(rgb, function(w) which.min(abs(wl - w)), integer(1)))
  }
  as.integer(rgb)
}

# Build a display data frame (x, y, and either fill hex or value) from an image.
.image_display_df <- function(img, level, bands, rgb, max_dim) {
  tile <- at_tile(img, level = level)
  nr <- dim(tile)[1]
  nc <- dim(tile)[2]
  full_nr <- nr; full_nc <- nc
  scale <- at_dims(img, 0L) / at_dims(img, level)
  fac <- max(1L, ceiling(max(nr, nc) / max_dim))
  ys <- seq(1L, nr, by = fac)
  xs <- seq(1L, nc, by = fac)
  tile <- tile[ys, xs, , drop = FALSE]
  nr <- dim(tile)[1]
  nc <- dim(tile)[2]
  rgb_bands <- .resolve_rgb(img, rgb)
  if (is.null(rgb_bands) && is.null(bands) && dim(tile)[3] >= 3L) {
    rgb_bands <- 1:3
  }
  # Contrast stretch to [0, 1] over finite samples; non-finite samples stay
  # NA and are drawn transparent. An 8-bit image keeps its stored values (see
  # .display_native()); otherwise a natural-colour (default) composite stretches
  # its three channels jointly so their colour balance is kept, and an explicit
  # `rgb` false-colour composite stretches each channel on its own.
  # Samples are handled as column-major vectors (y fastest, matching `grid`),
  # so one-row or one-column tiles need no matrix shape.
  band <- function(k) as.vector(tile[, , k, drop = FALSE])
  norm <- function(v, rng = .finite_range(v)) {
    out <- rep(NA_real_, length(v))
    ok <- is.finite(v)
    if (!any(ok)) {
      return(out)
    }
    out[ok] <- if (diff(rng) == 0) 0 else (v[ok] - rng[1]) / diff(rng)
    out
  }
  grid <- expand.grid(iy = seq_along(ys), ix = seq_along(xs))
  grid$xmin <- (xs[grid$ix] - 1) * scale[1]
  grid$xmax <- pmin(xs[grid$ix] - 1 + fac, full_nc) * scale[1]
  grid$ymin <- (ys[grid$iy] - 1) * scale[2]
  grid$ymax <- pmin(ys[grid$iy] - 1 + fac, full_nr) * scale[2]
  grid$x <- (grid$xmin + grid$xmax) / 2
  grid$y <- (grid$ymin + grid$ymax) / 2
  if (!is.null(rgb_bands) && length(rgb_bands) == 3L) {
    native <- is.null(rgb) && .display_native(img, tile[, , rgb_bands, drop = FALSE])
    joint <- if (is.null(rgb)) .finite_range(tile[, , rgb_bands, drop = FALSE]) else NULL
    ch <- lapply(rgb_bands, function(k) {
      if (native) .native01(band(k)) else if (is.null(joint)) norm(band(k)) else norm(band(k), joint)
    })
    r <- ch[[1]]; g <- ch[[2]]; b <- ch[[3]]
    ok <- !is.na(r) & !is.na(g) & !is.na(b)
    grid$fill <- NA_character_
    grid$fill[ok] <- grDevices::rgb(r[ok], g[ok], b[ok])
    grid$mode <- "rgb"
  } else {
    b1 <- if (!is.null(bands)) bands[1] else 1L
    grid$value <- band(b1)
    grid$mode <- "single"
  }
  attr(grid, "fac") <- fac
  grid
}

# Eight-bit images (RGB photographs, H&E scans, greyscale) are displayed with
# their stored values: a contrast stretch would shift their colour balance.
# Deeper, float and multichannel data are stretched for display.
# `values` are the samples about to be shown: the image must also hold whole
# numbers in [0, 255], so a hand-built image with the default dtype but other
# data is still stretched.
.display_native <- function(img, values = NULL) {
  if (!identical(img$dtype, "uint8") || !isTRUE(img$n_bands <= 4L)) {
    return(FALSE)
  }
  if (is.null(values)) {
    return(TRUE)
  }
  v <- as.vector(values)
  v <- v[!is.na(v)]
  all(is.finite(v)) && all(v >= 0 & v <= 255 & v == round(v))
}

# Stored 8-bit samples as display intensities in [0, 1]; non-finite are NA.
.native01 <- function(v) {
  out <- pmin(pmax(v / 255, 0), 1)
  out[!is.finite(v)] <- NA_real_
  out
}

# Range of the finite values of `x`, or c(0, 0) when there are none.
.finite_range <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) c(0, 0) else range(x)
}

#' Plot an image
#'
#' @param img An [annot_image].
#' @param level Pyramid level to sample; chosen automatically when `NULL`.
#'   Plot axes always use level-0 image coordinates, scaled independently by
#'   actual width and height ratios.
#' @param bands Optional band index for single-band display.
#' @param rgb Optional length-3 vector of band indices, or wavelengths in nm for
#'   a spectral cube, for a false-colour composite. Each channel of an `rgb`
#'   composite is contrast-stretched on its own; the default natural-colour
#'   display of an image with three or more bands shows an 8-bit image with its
#'   stored values and stretches deeper data in its first three bands jointly,
#'   preserving their colour balance.
#' @param max_dim Maximum display dimension (auto-downsampled). Default `1024`.
#'   Each displayed cell covers its full source block; final partial blocks
#'   end at the image boundary. When `level` is `NULL`, the finest pyramid
#'   level that fits within `max_dim` is sampled.
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object. Non-finite samples are drawn transparent.
#' @family plots
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE)
#' at_plot_image(at_example_image("tissue"))
at_plot_image <- function(img, level = NULL, bands = NULL, rgb = NULL,
                          max_dim = 1024L, call = rlang::caller_env()) {
  .check_image(img, call = call)
  max_dim <- .check_count(max_dim, min = 1L, call = call)
  if (is.null(level)) level <- .display_level(img, max_dim)
  df <- .image_display_df(img, level, bands, rgb, max_dim)
  p <- ggplot2::ggplot(df, ggplot2::aes(x = .data$x, y = .data$y)) +
    ggplot2::scale_y_reverse() +
    ggplot2::coord_fixed() +
    ggplot2::labs(title = basename(img$source), x = "x (px)", y = "y (px)") +
    ggplot2::theme_minimal()
  if (identical(df$mode[1], "rgb")) {
    p + ggplot2::geom_rect(ggplot2::aes(xmin = .data$xmin, xmax = .data$xmax,
                                      ymin = .data$ymin, ymax = .data$ymax, fill = .data$fill)) +
      ggplot2::scale_fill_identity(na.value = NA)
  } else {
    p + ggplot2::geom_rect(ggplot2::aes(xmin = .data$xmin, xmax = .data$xmax,
                                      ymin = .data$ymin, ymax = .data$ymax, fill = .data$value)) +
      ggplot2::scale_fill_viridis_c(name = "value", na.value = NA)
  }
}

# Assemble an sf of a project's ROIs (level 0) for spatial plotting.
.project_sf <- function(project, layer = NULL, label = NULL) {
  rt <- at_rois(project, layer = layer, label = label)
  if (nrow(rt) == 0L) {
    return(sf::st_sf(label = character(0), layer = character(0),
                     geometry = sf::st_sfc(crs = sf::NA_crs_)))
  }
  sf::st_sf(label = rt$label, layer = rt$layer, geometry = rt$geometry)
}

# Okabe-Ito fill scale keyed to a set of labels.
.label_fill_scale <- function(labels) {
  pal <- .resolve_palette(unique(labels))
  ggplot2::scale_fill_manual(values = pal, drop = FALSE)
}

#' Plot a project's ROIs
#'
#' @param project An [annot_project].
#' @param layer,label Optional filters.
#' @param show_labels Logical; draw label text at centroids. Default `TRUE`.
#' @param alpha Fill opacity; a sensible default when `NULL`.
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object in level-0 image coordinates with the
#'   y axis pointing down, as in the image. Empty projects give a valid empty
#'   plot.
#' @family plots
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE)
#' at_plot_project(at_example_project())
at_plot_project <- function(project, layer = NULL, label = NULL,
                            show_labels = TRUE, alpha = NULL,
                            call = rlang::caller_env()) {
  .check_project(project, call = call)
  sfp <- .project_sf(project, layer, label)
  a <- alpha %||% 0.4
  drawn <- .sf_display_data(sfp)
  p <- ggplot2::ggplot(sfp) +
    ggplot2::labs(title = project$meta$name %||% "project", x = "x (px)", y = "y (px)") +
    ggplot2::theme_minimal()
  if (nrow(sfp) > 0L) {
    p <- p + ggplot2::geom_sf(data = drawn, ggplot2::aes(fill = .data$label), alpha = a) +
      .label_fill_scale(sfp$label)
    if (show_labels) {
      cent <- sf::st_coordinates(suppressWarnings(sf::st_point_on_surface(sf::st_geometry(drawn))))
      lab_df <- data.frame(x = cent[, 1], y = cent[, 2], label = sfp$label)
      p <- p + ggplot2::geom_text(data = lab_df,
                                  ggplot2::aes(x = .data$x, y = .data$y, label = .data$label),
                                  size = 3, colour = "black")
    }
  }
  # Last: geom_sf() supplies a default coord_sf() that would replace it.
  p + .sf_image_coord()
}

#' Plot a mask
#'
#' @param mask An `annot_mask`.
#' @param legend Logical; show the fill legend. Default `TRUE`.
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object.
#' @family plots
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE)
#' at_plot_mask(at_mask(at_example_project(), "labelled"))
at_plot_mask <- function(mask, legend = TRUE, call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  plot(mask, legend = legend)
}

#' Plot spectra
#'
#' @param spectra The long tibble from [at_extract_spectrum()] or [at_extract()].
#'   Its declared `unit` is used on the axis; absent units remain unknown.
#'   Mixed units reject: explicitly convert coordinates before combining them.
#' @param colour_by One of `"label"`, `"roi_id"`, or `"layer"`.
#' @param ribbon Logical; draw a min-max ribbon per colour group (and
#'   statistic) wherever the group holds more than one ROI. Default `TRUE`.
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object with one line per ROI and statistic.
#' @family plots
#' @export
at_plot_spectrum <- function(spectra, colour_by = c("label", "roi_id", "layer"),
                             ribbon = TRUE, call = rlang::caller_env()) {
  colour_by <- .check_choice(colour_by, c("label", "roi_id", "layer"), default = missing(colour_by), call = call)
  spectra <- spectra[!is.na(spectra$wavelength), , drop = FALSE]
  units <- unique(spectra$unit %||% NA_character_)
  if (!length(units)) units <- NA_character_
  if (length(units) > 1L) .at_abort("Spectrum wavelength units must agree; explicitly convert units before plotting.", call = call)
  axis <- if (is.na(units) || !nzchar(units)) "spectral coordinate (unit unknown)" else paste0("spectral coordinate (", units, ")")
  .check_flag(ribbon, call = call)
  # One line per ROI and statistic: grouping by ROI alone zig-zags between the
  # statistics of a multi-statistic extraction.
  stat <- if ("stat" %in% names(spectra)) spectra$stat else rep("value", nrow(spectra))
  spectra$.line <- paste(spectra$roi_id, stat, sep = "\r")
  spectra$.band <- paste(spectra[[colour_by]], stat, sep = "\r")
  p <- ggplot2::ggplot(spectra, ggplot2::aes(x = .data$wavelength, y = .data$value,
                                             colour = .data[[colour_by]],
                                             group = .data$.line)) +
    ggplot2::labs(title = "Spectra", x = axis, y = "value",
                  colour = colour_by) +
    ggplot2::theme_minimal()
  if (nrow(spectra) > 0L && ribbon) {
    rb <- .spectrum_ribbon(spectra, colour_by)
    if (nrow(rb) > 0L) {
      p <- p + ggplot2::geom_ribbon(
        data = rb,
        ggplot2::aes(x = .data$wavelength, ymin = .data$lo, ymax = .data$hi,
                     fill = .data[[colour_by]], group = .data$.band),
        alpha = 0.2, colour = NA, inherit.aes = FALSE, show.legend = FALSE
      )
    }
  }
  if (nrow(spectra) > 0L) {
    p <- p + ggplot2::geom_line()
  }
  p
}

# Min-max envelope per colour group, statistic and wavelength, for groups that
# hold more than one ROI.
.spectrum_ribbon <- function(spectra, colour_by) {
  keys <- unique(spectra$.band)
  rows <- lapply(keys, function(k) {
    s <- spectra[spectra$.band == k, , drop = FALSE]
    if (length(unique(s$roi_id)) < 2L) {
      return(NULL)
    }
    wl <- sort(unique(s$wavelength))
    lo <- vapply(wl, function(w) min(s$value[s$wavelength == w], na.rm = TRUE), double(1))
    hi <- vapply(wl, function(w) max(s$value[s$wavelength == w], na.rm = TRUE), double(1))
    out <- data.frame(wavelength = wl, lo = lo, hi = hi, .band = k)
    out[[colour_by]] <- s[[colour_by]][1]
    out[is.finite(out$lo) & is.finite(out$hi), , drop = FALSE]
  })
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0L) {
    return(data.frame(wavelength = double(0), lo = double(0), hi = double(0)))
  }
  do.call(rbind, rows)
}

#' Plot ROIs overlaid on the image
#'
#' @param project An [annot_project].
#' @param img An [annot_image]; the project's image by default.
#' @param layer Optional layer filter.
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object with the image and ROI outlines (points
#'   as markers), both in level-0 image coordinates.
#' @family plots
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE)
#' at_plot_overlay(at_example_project())
at_plot_overlay <- function(project, img = NULL, layer = NULL,
                            call = rlang::caller_env()) {
  .check_project(project, call = call)
  if (is.null(img)) img <- project$image
  base <- at_plot_image(img, call = call)
  rt <- at_rois(project, layer = layer)
  if (nrow(rt) > 0L) {
    # Draw outlines with geom_path (not geom_sf) to keep coord_fixed consistent
    # with the raster and avoid a coordinate-system clash. Each ROI is split
    # into its parts, so mixed geometry types (polygons, lines, points) and
    # repaired GEOMETRYCOLLECTIONs all draw.
    parts <- lapply(seq_len(nrow(rt)), function(k) .overlay_parts(rt$geometry[[k]], k, rt$label[k]))
    paths <- do.call(rbind, lapply(parts, `[[`, "paths"))
    points <- do.call(rbind, lapply(parts, `[[`, "points"))
    if (!is.null(paths) && nrow(paths) > 0L) {
      base <- base +
        ggplot2::geom_path(data = paths,
                           ggplot2::aes(x = .data$x, y = .data$y,
                                        group = .data$group, colour = .data$label),
                           linewidth = 0.7, inherit.aes = FALSE)
    }
    if (!is.null(points) && nrow(points) > 0L) {
      base <- base +
        ggplot2::geom_point(data = points,
                            ggplot2::aes(x = .data$x, y = .data$y, colour = .data$label),
                            shape = 3, size = 2.5, stroke = 1, inherit.aes = FALSE)
    }
    base <- base + ggplot2::labs(colour = "label")
  }
  base
}

# Outline paths and point markers for one ROI geometry (an sfg). Rings and
# lines become groups of path vertices; points become markers.
.overlay_parts <- function(g, k, label) {
  paths <- list()
  points <- list()
  walk <- function(g, tag) {
    if (inherits(g, "GEOMETRYCOLLECTION")) {
      for (i in seq_along(g)) walk(g[[i]], paste0(tag, "_", i))
      return(invisible(NULL))
    }
    co <- sf::st_coordinates(g)
    if (nrow(co) == 0L) {
      return(invisible(NULL))
    }
    if (inherits(g, c("POINT", "MULTIPOINT"))) {
      points[[length(points) + 1L]] <<- data.frame(x = co[, "X"], y = co[, "Y"], label = label)
      return(invisible(NULL))
    }
    lcols <- setdiff(colnames(co), c("X", "Y", "Z", "M"))
    grp <- if (length(lcols)) apply(co[, lcols, drop = FALSE], 1L, paste, collapse = "_") else "1"
    paths[[length(paths) + 1L]] <<- data.frame(
      x = co[, "X"], y = co[, "Y"], group = paste(k, tag, grp, sep = ":"), label = label
    )
  }
  walk(g, "g")
  list(paths = if (length(paths)) do.call(rbind, paths) else NULL,
       points = if (length(points)) do.call(rbind, points) else NULL)
}

#' Plot a project summary
#'
#' @param project An [annot_project].
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object of per-label ROI area distributions.
#' @family plots
#' @export
at_plot_summary <- function(project, call = rlang::caller_env()) {
  .check_project(project, call = call)
  rt <- at_rois(project)
  rt <- sf::st_drop_geometry(rt)
  p <- ggplot2::ggplot(rt, ggplot2::aes(x = .data$label, y = .data$area_px,
                                        fill = .data$label)) +
    ggplot2::labs(title = "ROI area by label", x = "label", y = "area (px)") +
    ggplot2::theme_minimal() +
    ggplot2::theme(legend.position = "none")
  if (nrow(rt) > 0L) {
    p <- p + ggplot2::geom_boxplot(alpha = 0.5) +
      ggplot2::geom_jitter(width = 0.15, height = 0, size = 1) +
      .label_fill_scale(rt$label)
  }
  p
}

#' Plot generic for hyperannotatR objects
#'
#' @param x An [annot_image], [annot_project], [annot_layer], or `annot_mask`.
#' @param ... Passed to the specific plot function. For layers, passed to
#'   [at_layer_rois()]: supply `image = img` for any nonzero stored ROI level.
#'   Layer plot geometry uses level-0 coordinates. The same image argument is
#'   supported by `ggplot2::autoplot(layer, image = img)`.
#' @return A [ggplot2::ggplot] object.
#' @family plots
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE)
#' at_plot(at_example_project())
at_plot <- function(x, ...) {
  if (inherits(x, "annot_image")) return(at_plot_image(x, ...))
  if (inherits(x, "annot_project")) return(at_plot_project(x, ...))
  if (inherits(x, "annot_mask")) return(at_plot_mask(x, ...))
  if (inherits(x, "annot_layer")) {
    rt <- at_layer_rois(x, ...)
    sfp <- if (nrow(rt) > 0L) {
      sf::st_sf(label = rt$label, geometry = rt$geometry)
    } else {
      sf::st_sf(label = character(0), geometry = sf::st_sfc(crs = sf::NA_crs_))
    }
    p <- ggplot2::ggplot(sfp) +
      ggplot2::labs(title = x$name, x = "x (px)", y = "y (px)") +
      ggplot2::theme_minimal()
    if (nrow(sfp) > 0L) {
      p <- p + ggplot2::geom_sf(data = .sf_display_data(sfp),
                                ggplot2::aes(fill = .data$label), alpha = 0.4) +
        .label_fill_scale(sfp$label)
    }
    return(p + .sf_image_coord())
  }
  .at_abort("No {.fn at_plot} method for {.cls {class(x)[1]}}.")
}

#' @exportS3Method ggplot2::autoplot
autoplot.annot_project <- function(object, ...) at_plot_project(object, ...)

#' @exportS3Method ggplot2::autoplot
autoplot.annot_image <- function(object, ...) at_plot_image(object, ...)

#' @exportS3Method ggplot2::autoplot
autoplot.annot_mask <- function(object, ...) at_plot_mask(object, ...)

#' @exportS3Method ggplot2::autoplot
autoplot.annot_layer <- function(object, ...) at_plot(object, ...)
