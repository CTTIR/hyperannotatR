is_gg <- function(p) inherits(p, "ggplot")

test_that("spatial plots return ggplot objects", {
  skip_if_not_installed("tiff")
  proj <- at_example_project()
  expect_true(is_gg(at_plot_image(at_example_image("tissue"))))
  expect_true(is_gg(at_plot_project(proj)))
  expect_true(is_gg(at_plot_overlay(proj)))
  expect_true(is_gg(at_plot_summary(proj)))
  expect_true(is_gg(at_plot_mask(at_mask(proj, "labelled"))))
})

test_that("RGB and spectral false-colour composites work", {
  skip_if_not_installed("tiff")
  expect_true(is_gg(at_plot_image(at_example_image("multiplex"), rgb = c(4, 2, 1))))
  expect_true(is_gg(at_plot_image(at_example_image("cube"), rgb = c(650, 550, 450))))
})

test_that("at_plot_spectrum returns a ggplot", {
  skip_if_not_installed("tiff")
  cube <- at_example_image("cube")
  lyr <- at_layer_add(at_layer("r", labels = "a"), at_roi_circle(38, 38, 4, label = "a"))
  sp <- at_extract_spectrum(at_project(cube, lyr))
  expect_true(is_gg(at_plot_spectrum(sp)))
  expect_true(is_gg(at_plot_spectrum(sp, colour_by = "roi_id")))
})

test_that("the at_plot generic and autoplot dispatch", {
  proj <- demo_project()
  data_img <- new_annot_image("k.tif", "raster", c(4L, 4L), 1L, list(c(4L, 4L)), 1L,
                              handle = list(data = array(1, dim = c(4, 4, 1))),
                              dtype = "uint8")
  expect_true(is_gg(at_plot(proj)))
  expect_true(is_gg(at_plot(data_img)))
  expect_true(is_gg(at_plot(proj$layers$tissue)))
  expect_true(is_gg(ggplot2::autoplot(proj)))
  expect_true(is_gg(ggplot2::autoplot(at_mask(proj, "labelled"))))
})

test_that("plots do not error on empty input", {
  ep <- at_project(small_image())
  expect_true(is_gg(at_plot_project(ep)))
  expect_true(is_gg(at_plot_summary(ep)))
  expect_true(is_gg(at_plot_spectrum(.empty_extract_tbl())))
})

test_that("no plot function draws to a device when called", {
  # ggplot construction is lazy; building must not open a device.
  before <- length(grDevices::dev.list())
  invisible(at_plot_project(demo_project()))
  invisible(at_plot_summary(demo_project()))
  expect_equal(length(grDevices::dev.list()), before)
})

test_that("the display level is the finest level within max_dim (W13)", {
  img <- new_annot_image("p.tif", "tiff", c(1000L, 800L), 3L,
                         list(c(1000L, 800L), c(500L, 400L), c(250L, 200L)), 1L)
  expect_identical(.display_level(img, 1024L), 0L)
  expect_identical(.display_level(img, 600L), 1L)
  expect_identical(.display_level(img, 300L), 2L)
  # Nothing fits: the coarsest level needs the least downsampling.
  expect_identical(.display_level(img, 100L), 2L)
})

test_that("overlays draw mixed polygon, line and point ROIs (M14)", {
  img <- new_annot_image("k.tif", "raster", c(10L, 10L), 1L, list(c(10L, 10L)), 1L,
                         handle = list(data = array(1, c(10, 10, 1))))
  lyr <- at_layer_add(at_layer("l"), at_roi_rect(1, 1, 4, 4, label = "a"))
  lyr <- at_layer_add(lyr, at_roi_point(6, 6, label = "p"))
  p <- at_plot_overlay(at_project(img, lyr))
  # Built data hold the reversed-scale y, i.e. -y.
  built <- ggplot2::ggplot_build(p)$data
  paths <- built[[2]]
  points <- built[[3]]
  expect_equal(range(paths$x), c(1, 4))
  expect_equal(range(-paths$y), c(1, 4))
  expect_equal(c(points$x, -points$y), c(6, 6))
  # An all-point project draws markers only.
  only <- at_project(img, at_layer_add(at_layer("l"), at_roi_point(2, 3, label = "p")))
  built <- ggplot2::ggplot_build(at_plot_overlay(only))$data
  expect_equal(c(built[[2]]$x, -built[[2]]$y), c(2, 3))
})

test_that("natural colour keeps channel balance and non-finite pixels are transparent (M18)", {
  arr <- array(0, c(2, 2, 3))
  arr[, , 1] <- c(100, 200, 100, 200)
  arr[, , 2] <- c(50, 100, 50, 100)
  arr[, , 3] <- c(0, 0, 0, 0)
  img <- new_annot_image("rgb.tif", "raster", c(2L, 2L), 1L, list(c(2L, 2L)), 3L,
                         dtype = "uint16", handle = list(data = arr))
  df <- .image_display_df(img, 0L, NULL, NULL, 1024L)
  # One joint stretch over [0, 200]: row 2 keeps G = R / 2, row 1 half of it.
  expect_identical(df$fill[df$x == 1.5 & df$y == 1.5], grDevices::rgb(1, 0.5, 0))
  expect_identical(df$fill[df$x == 1.5 & df$y == 0.5], grDevices::rgb(0.5, 0.25, 0))
  # An explicit composite stretches each channel on its own.
  df2 <- .image_display_df(img, 0L, NULL, c(1, 2, 3), 1024L)
  expect_identical(df2$fill[df2$x == 1.5 & df2$y == 1.5], grDevices::rgb(1, 1, 0))
  arr[1, 1, 2] <- NaN
  arr[2, 2, 1] <- Inf
  img <- new_annot_image("rgb-nonfinite.tif", "raster", c(2L, 2L), 1L, list(c(2L, 2L)), 3L,
                         dtype = "uint16", handle = list(data = arr))
  df3 <- .image_display_df(img, 0L, NULL, NULL, 1024L)
  expect_identical(sum(is.na(df3$fill)), 2L)
  expect_no_error(ggplot2::ggplot_build(at_plot_image(img)))
})

test_that("sf plots point the y axis down like the image (M19)", {
  img <- new_annot_image("k.tif", "raster", c(200L, 100L), 1L, list(c(200L, 100L)), 1L)
  lyr <- at_layer_add(at_layer("l"), at_roi_rect(0, 0, 60, 20, label = "top"))
  proj <- at_project(img, lyr)
  for (p in list(at_plot_project(proj), at_plot(lyr))) {
    # Plot data keep image coordinates whichever way the axis is drawn.
    expect_equal(as.numeric(sf::st_bbox(p$data$geometry)), c(0, 0, 60, 20))
    if (.coord_sf_reverse_y()) {
      expect_identical(p$coordinates$reverse, "y")
    }
  }
  # Without coord_sf(reverse=), the drawn geometry is mirrored instead.
  testthat::local_mocked_bindings(.coord_sf_reverse_y = function() FALSE)
  p <- at_plot_project(proj, show_labels = FALSE)
  drawn <- ggplot2::ggplot_build(p)$data[[1]]$geometry
  expect_equal(as.numeric(sf::st_bbox(drawn)), c(0, -20, 60, 0))
  expect_equal(as.numeric(sf::st_bbox(p$data$geometry)), c(0, 0, 60, 20))
})

test_that("spectra draw one line per ROI and statistic with ribbons", {
  sp <- tibble::tibble(
    roi_id = rep(c("r1", "r2"), each = 4), layer = "l", label = "a",
    band = rep(1:2, 4), wavelength = rep(c(500, 600), 4),
    unit = "nm", stat = rep(rep(c("mean", "median"), each = 2), 2),
    value = c(1, 2, 1.5, 2.5, 3, 4, 3.5, 4.5)
  )
  b <- ggplot2::ggplot_build(at_plot_spectrum(sp))$data
  lines <- b[[2]]
  expect_identical(length(unique(lines$group)), 4L)
  ribbon <- b[[1]]
  expect_equal(sort(unique(ribbon$ymin)), c(1, 1.5, 2, 2.5))
  expect_length(ggplot2::ggplot_build(at_plot_spectrum(sp, ribbon = FALSE))$data, 1L)
})

test_that("one-row and one-column images plot (single band and RGB)", {
  for (d in list(c(5L, 1L), c(1L, 4L))) {
    for (nb in c(1L, 3L)) {
      arr <- array(seq_len(prod(d) * nb), c(d[2], d[1], nb))
      img <- new_annot_image(paste0("strip-", d[1], "x", d[2], "-", nb, ".tif"), "raster",
                             d, 1L, list(d), nb, handle = list(data = arr))
      df <- .image_display_df(img, 0L, NULL, NULL, 1024L)
      expect_identical(nrow(df), as.integer(prod(d)))
      expect_no_error(ggplot2::ggplot_build(at_plot_image(img)))
    }
  }
})

test_that("the default display of an 8-bit RGB image keeps its stored colours", {
  skip_if_not_installed("magick")
  img <- at_example_image("tissue")
  px <- at_tile(img, xrange = c(180, 180), yrange = c(200, 200))
  expect_equal(as.vector(px), c(192, 95, 167))
  d <- .image_display_df(img, level = 0L, bands = NULL, rgb = NULL, max_dim = 1024L)
  hit <- d$fill[d$ix == 180 & d$iy == 200]
  expect_identical(hit, grDevices::rgb(192, 95, 167, maxColorValue = 255))
  # An explicit false-colour composite is still stretched channel by channel.
  d2 <- .image_display_df(img, level = 0L, bands = NULL, rgb = 3:1, max_dim = 1024L)
  expect_false(identical(d2$fill[d2$ix == 180 & d2$iy == 200],
                         grDevices::rgb(167, 95, 192, maxColorValue = 255)))
})

test_that("an image labelled 8-bit but holding other values is stretched", {
  arr <- array(c(0, 1000, 500, 250), c(2, 2, 3))
  img <- new_annot_image("wide.tif", "raster", c(2L, 2L), 1L, list(c(2L, 2L)), 3L,
                         handle = list(data = arr))
  expect_identical(img$dtype, "uint8")
  expect_false(.display_native(img, arr))
  df <- .image_display_df(img, 0L, NULL, NULL, 1024L)
  # 500 of a joint [0, 1000] stretch is mid-grey; read as 8-bit it would clamp to white.
  expect_identical(df$fill[df$x == 1.5 & df$y == 0.5], grDevices::rgb(0.5, 0.5, 0.5))
})

test_that("mask plots and previews frame the whole image in image coordinates", {
  skip_if_not_installed("magick")
  m <- at_mask(at_example_project(), "labelled")
  pv <- at_mask_preview(m, max_dim = 100L)
  for (mm in list(m, pv)) {
    pp <- ggplot2::ggplot_build(plot(mm))$layout$panel_params[[1]]
    expect_equal(pp$x.range, c(0, 512))
    expect_equal(sort(abs(pp$y.range)), c(0, 512))
  }
  # Preview cells are placed back in image pixels, not preview pixels.
  tiles <- ggplot2::ggplot_build(plot(pv))$data[[2]]
  expect_gt(max(tiles$x), 400)
  expect_lt(max(tiles$x), 520)
})

# A project on the bundled cube whose layer declares its own label colours.
styled_cube_project <- function() {
  lyr <- at_layer("tissue", labels = c("tumour", "stroma"),
                  style = at_style(colour = c(tumour = "#FF0000", stroma = "#0000FF")))
  lyr <- at_layer_add(lyr, at_roi_rect(10, 10, 40, 40, label = "stroma"))
  lyr <- at_layer_add(lyr, at_roi_rect(50, 50, 60, 60, label = "stroma"))
  lyr <- at_layer_add(lyr, at_roi_circle(90, 90, 15, label = "tumour"))
  at_project(at_example_image("cube"), lyr)
}

layer_colours <- function(p, k, aes = "fill") {
  d <- ggplot2::ggplot_build(p)$data[[k]]
  toupper(unique(d[[aes]]))
}

test_that("project, layer, overlay and summary plots use the layer's style colours", {
  proj <- styled_cube_project()
  # ROI order is stroma, stroma, tumour: a palette keyed to ROI order would
  # give stroma the first default colour instead of its declared blue.
  expect_identical(layer_colours(at_plot_project(proj), 1L), c("#0000FF", "#FF0000"))
  expect_identical(layer_colours(at_plot(proj$layers$tissue), 1L), c("#0000FF", "#FF0000"))
  expect_identical(layer_colours(at_plot_summary(proj), 1L), c("#0000FF", "#FF0000"))
  expect_identical(layer_colours(at_plot_overlay(proj), 2L, "colour"), c("#0000FF", "#FF0000"))
  # The mask of the same project shows the same colours.
  lg <- at_mask_legend(at_mask(proj, "labelled"))
  expect_identical(toupper(lg$colour[match(c("stroma", "tumour"), lg$label)]),
                   c("#0000FF", "#FF0000"))
})

test_that("plots of a project without declared colours keep the default palette by label", {
  proj <- demo_project()
  pal <- .project_palette(proj, c("tumour", "tissue"))
  expect_identical(pal[["tissue"]], proj$layers$tissue$style$colour[["tissue"]])
  expect_identical(pal[["tumour"]], proj$layers$tumour$style$colour[["tumour"]])
  # A label unknown to every layer still gets a colour.
  expect_false(anyNA(.project_palette(proj, c("tissue", "other"))))
  # Restricting to one layer uses that layer's colours.
  expect_identical(.project_palette(proj, "tumour", layer = "tumour")[["tumour"]],
                   proj$layers$tumour$style$colour[["tumour"]])
})

test_that("a spectrum ribbon has the colour of its own lines", {
  proj <- styled_cube_project()
  sp <- at_extract_spectrum(proj)
  b <- ggplot2::ggplot_build(at_plot_spectrum(sp))
  ribbon <- b$data[[1]]
  lines <- b$data[[2]]
  # Only stroma holds two ROIs, so only stroma has a ribbon. A fill scale
  # trained on the ribbon data alone would colour it like another group.
  stroma <- .group_palette(sp$label)[["stroma"]]
  expect_identical(unique(ribbon$fill), stroma)
  expect_true(stroma %in% lines$colour)
  expect_length(unique(lines$colour), 2L)
  expect_true(all(unique(lines$colour) %in% .okabe_ito()))
})

test_that("spectrum groups beyond the palette size stay distinguishable", {
  pal <- .group_palette(paste0("roi", 1:12))
  expect_length(unique(pal), 12L)
  expect_named(pal, paste0("roi", 1:12))
  expect_identical(unname(.group_palette(c("a", "b"))), .okabe_ito()[1:2])
})

test_that("plot arguments are validated with classified errors", {
  cube <- at_example_image("cube")
  expect_error(at_plot_image(cube, bands = 99), class = "at_validation_error")
  expect_error(at_plot_image(cube, bands = 0), class = "at_validation_error")
  expect_error(at_plot_image(cube, bands = "a"), class = "at_validation_error")
  expect_error(at_plot_image(cube, rgb = c(1, 2)), class = "at_validation_error")
  expect_error(at_plot_image(cube, rgb = c(1, NA, 3)), class = "at_validation_error")
  expect_error(at_plot_image(cube, rgb = c("a", "b", "c")), class = "at_validation_error")
  expect_error(at_plot_image(cube, rgb = c(0, 1, 2)), class = "at_validation_error")
  # A non-spectral image has no wavelengths to fall back on.
  expect_error(at_plot_image(small_image(), rgb = c(1, 2, 9)), class = "at_validation_error")
  # Valid selections still plot: band indices and wavelengths.
  expect_true(is_gg(at_plot_image(cube, bands = 40)))
  expect_true(is_gg(at_plot_image(cube, rgb = c(30, 20, 10))))
  expect_true(is_gg(at_plot_image(cube, rgb = c(650, 550, 450))))

  proj <- demo_project()
  expect_error(at_plot_project(proj, alpha = 5), class = "at_validation_error")
  expect_error(at_plot_project(proj, alpha = "a"), class = "at_validation_error")
  expect_error(at_plot_project(proj, show_labels = NA), class = "at_validation_error")
  expect_true(is_gg(at_plot_project(proj, alpha = 1, show_labels = FALSE)))
  m <- at_mask(proj, "labelled")
  expect_error(at_plot_mask(m, legend = NA), class = "at_validation_error")
  expect_error(plot(m, legend = "yes"), class = "at_validation_error")

  expect_error(at_plot_spectrum(NULL), class = "at_validation_error")
  expect_error(at_plot_spectrum(data.frame(wavelength = 1)), class = "at_validation_error")
  expect_error(at_plot_spectrum(.empty_extract_tbl(), ribbon = NA), class = "at_validation_error")
})
