# Raster backend: display conversion of PNG, JPEG, BMP, GIF and single-plane
# TIFF to 0-255 samples (`meta$sample_contract = "display-converted-0-255"`).
# It is not a raw reader: high-bit-depth samples are scaled to 8-bit range.
# PNG, JPEG, BMP and GIF need `magick`; a TIFF uses `magick` when installed and
# otherwise `tiff`. Raw TIFF samples come from the tiff backend. No pyramid
# (n_levels = 1).

.raster_band_names <- function(nb) {
  switch(
    as.character(nb),
    "1" = "Gray",
    "2" = c("Gray", "Alpha"),
    "3" = c("R", "G", "B"),
    "4" = c("R", "G", "B", "Alpha"),
    paste0("Band ", seq_len(nb))
  )
}

.raster_is_tiff <- function(path) grepl("\\.tiff?$", path, ignore.case = TRUE)

.raster_read <- function(path, ..., call = rlang::caller_env()) {
  if (requireNamespace("magick", quietly = TRUE)) {
    m <- magick::image_read(path)
    # Request the channels explicitly: magick's default map for a grey image
    # with alpha is "gray", which drops the alpha and blends it into the grey
    # values.
    info <- magick::image_info(m)[1, ]
    channels <- paste0(if (identical(info$colorspace, "Gray")) "gray" else "rgb",
                       if (isTRUE(info$matte)) "a" else "")
    # A magick bitmap is a raw [channel, width, height] array. unclass() it
    # first: magick's as.integer() method already transposes to
    # [height, width, channel], so re-dimensioning its result as
    # [channel, width, height] would scramble every pixel.
    raw <- unclass(magick::image_data(m, channels = channels))
    d <- dim(raw) # [channels, width, height]
    arr <- aperm(array(as.integer(raw), d), c(3, 2, 1)) # [y, x, band], 0-255
    storage.mode(arr) <- "double"
    w <- d[2]
    h <- d[3]
    nb <- d[1]
    dtype <- "uint8"
  } else if (.raster_is_tiff(path) && requireNamespace("tiff", quietly = TRUE)) {
    t <- .tiff_read_isolated(path, as.is = FALSE, info = TRUE)
    if (identical(attr(t, "planar.config"), "separate")) {
      .at_abort("Planar-separate TIFF samples cannot be decoded exactly; write the image with contiguous (interleaved) samples.",
                class = "io", code = "TIFF_UNSUPPORTED", call = call)
    }
    attributes(t) <- list(dim = dim(t))
    if (length(dim(t)) == 2L) {
      t <- array(t, dim = c(dim(t), 1L))
    }
    arr <- t * 255 # readTIFF returns [0, 1]; match the 0-255 display convention
    h <- dim(arr)[1]
    w <- dim(arr)[2]
    nb <- dim(arr)[3]
    dtype <- "uint8"
  } else {
    .at_abort(c(
      "PNG, JPEG and other non-TIFF raster images require package {.pkg magick}; TIFF can also use {.pkg tiff}.",
      "i" = "Install one with {.code install.packages(\"magick\")}."
    ), class = "capability", code = "CAPABILITY_UNAVAILABLE", call = call)
  }
  new_annot_image(
    source = path, backend = "raster",
    dims = c(w, h), n_levels = 1L, level_dims = list(c(w, h)),
    n_bands = nb, band_names = .raster_band_names(nb),
    pixel_size = c(1, 1), pixel_unit = "px", dtype = dtype,
    handle = list(data = arr),
    meta = list(sample_contract = "display-converted-0-255",
                capabilities = .eager_capabilities("display-converted-0-255"))
  )
}

.raster_tile <- function(img, level, xrange, yrange, bands) {
  arr <- img$handle$data
  ys <- yrange[1]:yrange[2]
  xs <- xrange[1]:xrange[2]
  bs <- if (is.null(bands)) seq_len(img$n_bands) else bands
  arr[ys, xs, bs, drop = FALSE]
}

.raster_detect <- function(path) {
  grepl("\\.(png|jpe?g|bmp|gif|tiff?)$", path, ignore.case = TRUE)
}

# Usable when either decoder is installed; without magick only TIFF files can
# be read, and other formats fail with a capability error.
.raster_available <- function() {
  requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
}
