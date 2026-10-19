# TIFF backends.
#
# "tiff"    - pyramidal / multi-directory TIFF via the `tiff` package, holding
#             stored sample values. Directories must form a consistent
#             decreasing pyramid; equal-size planes are refused as ambiguous.
# "ometiff" - OME-TIFF, qptiff (Akoya PhenoImager), and vendor formats via
#             `RBioFormats` (Bioconductor, optional) and `xml2`. Opens metadata
#             only and reads native windows; preserves axes, levels, channel
#             names, emission wavelengths and physical pixel size.

# ---- tiff backend ----------------------------------------------------------

# Coerce decoded TIFF directories into a list of [y, x, band] double arrays,
# ordered by decreasing size (level 0 first).
.tiff_to_levels <- function(x) {
  imgs <- if (is.list(x)) x else list(x)
  imgs <- lapply(imgs, function(a) {
    if (length(dim(a)) == 2L) array(a, dim = c(dim(a), 1L)) else a
  })
  sizes <- vapply(imgs, function(a) dim(a)[1] * dim(a)[2], numeric(1))
  imgs <- imgs[order(sizes, decreasing = TRUE)]
  lapply(imgs, function(a) {
    storage.mode(a) <- "double"
    a
  })
}

# Decode every TIFF directory to its stored sample values. tiff's display path
# keeps floating samples but divides integer samples by 2^bits - 1 (and reads
# signed integers as unsigned), and readTIFF(as.is = TRUE) undoes that only for
# one-sample images, so integer codes are recovered here and checked to be
# exact. Only independently qualified sample types and photometric spaces are
# accepted; anything else is refused rather than returned approximately. The
# decoded directories carry a `raw_dtype` attribute ("uint8", "int16",
# "float32", ...).
.tiff_raw_read <- function(path, call = rlang::caller_env()) {
  if (!.tiff_available()) {
    .at_abort("Raw TIFF reading requires package {.pkg tiff}; display conversion cannot preserve mask/image samples.",
              class = "capability", code = "CAPABILITY_UNAVAILABLE", call = call)
  }
  imgs <- tryCatch(
    suppressWarnings(.tiff_read_isolated(path, all = TRUE, as.is = FALSE, info = TRUE)),
    error = function(e) {
      .at_abort("Unsupported or invalid raw TIFF encoding: {conditionMessage(e)}",
                class = "io", code = "TIFF_UNSUPPORTED", call = call)
    }
  )
  if (!is.list(imgs)) imgs <- list(imgs)
  unsupported <- function(msg) {
    .at_abort(msg, class = "io", code = "TIFF_UNSUPPORTED", call = call)
  }
  lapply(imgs, function(a) {
    # The tiff package decodes planar-separate samples (PlanarConfiguration 2)
    # as mostly zeros without an error (A35).
    if (identical(attr(a, "planar.config"), "separate")) {
      unsupported("Planar-separate TIFF samples cannot be decoded exactly; write the image with contiguous (interleaved) samples.")
    }
    bits <- attr(a, "bits.per.sample")
    format <- attr(a, "sample.format") %||% "uint"
    colour <- attr(a, "color.space")
    n_values <- as.double(attr(a, "width") %||% NA) * (attr(a, "length") %||% NA) *
      (attr(a, "samples.per.pixel") %||% NA)
    if (length(bits) != 1L || !isTRUE(format %in% c("uint", "int", "float")) ||
        !isTRUE(colour %in% c("black is zero", "RGB")) ||
        !(length(dim(a)) %in% c(2L, 3L)) || !isTRUE(prod(dim(a)) == n_values)) {
      unsupported("Unsupported TIFF sample type, colour space or channel layout; raw samples cannot be guaranteed.")
    }
    if (format == "float") {
      if (!bits %in% c(32L, 64L)) unsupported("Unsupported floating TIFF sample depth.")
    } else {
      if (!bits %in% c(8L, 16L)) {
        unsupported("Unsupported integer TIFF sample depth; the raw decoder supports 8/16-bit integers.")
      }
      a <- a * (2^bits - 1)
      if (any(!is.finite(a)) || any(abs(a - round(a)) > 1e-7) || any(a < 0 | a > 2^bits - 1)) {
        unsupported("The TIFF decoder did not return exact integer sample codes.")
      }
      a <- round(a)
      if (format == "int") a[a >= 2^(bits - 1)] <- a[a >= 2^(bits - 1)] - 2^bits
    }
    attr(a, "raw_dtype") <- paste0(format, bits)
    a
  })
}

# Parse channel names from an OME-XML / qptiff ImageDescription, degrading
# gracefully. Never errors.
.tiff_channel_names <- function(desc, n) {
  default <- paste0("Channel ", seq_len(n))
  if (is.null(desc) || !nzchar(desc)) {
    return(default)
  }
  nm <- tryCatch(
    {
      if (requireNamespace("xml2", quietly = TRUE) && grepl("<", desc, fixed = TRUE)) {
        doc <- xml2::read_xml(desc)
        ch <- xml2::xml_find_all(doc, "//*[local-name()='Channel']")
        vals <- xml2::xml_attr(ch, "Name")
        vals[!is.na(vals)]
      } else {
        m <- regmatches(desc, gregexpr("<Name>([^<]*)</Name>", desc, perl = TRUE))[[1]]
        sub("<Name>([^<]*)</Name>", "\\1", m)
      }
    },
    error = function(e) character(0)
  )
  if (length(nm) == n) nm else default
}

# Validate explicitly declared band-centre wavelengths for a TIFF. A TIFF is
# only treated as spectral when wavelengths are supplied; otherwise it stays a
# multichannel raster.
.tiff_wavelengths <- function(wavelengths, nb, call) {
  if (is.null(wavelengths)) {
    return(NULL)
  }
  wl <- suppressWarnings(as.numeric(wavelengths))
  if (length(wl) != nb || anyNA(wl)) {
    .at_abort("{.arg wavelengths} must give one numeric wavelength per band ({nb}).",
              code = "VALIDATION_FAILED", call = call)
  }
  wl
}

.tiff_read <- function(path, wavelengths = NULL, value_unit = NULL, ...,
                       call = rlang::caller_env()) {
  if (!requireNamespace("tiff", quietly = TRUE)) {
    cli::cli_abort(c(
      "The {.val tiff} backend requires package {.pkg tiff}.",
      "i" = "Install it with {.code install.packages(\"tiff\")}."
    ))
  }
  raw <- .tiff_raw_read(path, call = call)
  desc <- attr(raw[[1]], "description")
  dtype <- vapply(raw, attr, character(1), which = "raw_dtype")
  if (length(unique(dtype)) != 1L) {
    .at_abort("TIFF directories have incompatible sample types.", class = "io",
              code = "TIFF_UNSUPPORTED", call = call)
  }
  levels <- .tiff_to_levels(raw)
  level_dims <- lapply(levels, function(a) c(dim(a)[2], dim(a)[1]))
  nb <- dim(levels[[1]])[3]
  # Equal-size directories are independent planes (channels, z, time), whose
  # meaning a plain TIFF does not declare: refuse them instead of keeping one.
  inconsistent <- any(vapply(levels, function(a) dim(a)[3] != nb, logical(1))) ||
    (length(levels) > 1L && any(vapply(seq.int(2L, length(levels)), function(i) {
      any(level_dims[[i]] > level_dims[[i - 1L]]) || all(level_dims[[i]] == level_dims[[i - 1L]])
    }, logical(1))))
  if (inconsistent) {
    .at_abort(
      c("Ambiguous TIFF directories in {.file {basename(path)}}: only a consistent decreasing pyramid is supported.",
        "i" = "Use a format-specific reader (e.g. OME-TIFF) for independent planes or channels stored as pages."),
      class = "io", code = "TIFF_AMBIGUOUS", call = call
    )
  }
  wl <- .tiff_wavelengths(wavelengths, nb, call)
  new_annot_image(
    source = path, backend = "tiff",
    dims = level_dims[[1]], n_levels = length(levels), level_dims = level_dims,
    n_bands = nb, band_names = .tiff_channel_names(desc, nb),
    wavelengths = wl, wavelength_unit = if (is.null(wl)) NULL else "nm",
    pixel_size = c(1, 1), pixel_unit = "px", dtype = dtype[1],
    handle = list(levels = levels),
    meta = list(format = "TIFF", value_unit = value_unit %||% "unknown", window_read = FALSE,
                wavelength_source = if (is.null(wl)) "none" else "declared",
                reader_contract = list(axes = "yxb", samples = "raw-scalar-v1"),
                capabilities = .eager_capabilities())
  )
}

.tiff_tile <- function(img, level, xrange, yrange, bands) {
  arr <- img$handle$levels[[level + 1L]]
  ys <- yrange[1]:yrange[2]
  xs <- xrange[1]:xrange[2]
  bs <- if (is.null(bands)) seq_len(img$n_bands) else bands
  arr[ys, xs, bs, drop = FALSE]
}

.tiff_detect <- function(path) {
  grepl("\\.(tiff?)$", path, ignore.case = TRUE) &&
    !grepl("\\.(ome\\.tif|ome\\.tiff|qptiff)$", path, ignore.case = TRUE)
}

.tiff_available <- function() requireNamespace("tiff", quietly = TRUE)

# ---- ometiff backend (RBioFormats) -----------------------------------------

# Open an OME-TIFF / qptiff by metadata only: dimensions, levels, channels,
# emission wavelengths and physical pixel size come from Bio-Formats core
# metadata and the OME-XML; pixels are read later as native windows
# (.ome_window()). Z and time axes and multiple series need an explicit
# selection, so they are refused instead of being flattened.
.ometiff_read <- function(path, series = NULL, ..., call = rlang::caller_env()) {
  if (!requireNamespace("RBioFormats", quietly = TRUE) || !requireNamespace("xml2", quietly = TRUE)) {
    .at_abort("The {.val ometiff} backend requires packages {.pkg RBioFormats} and {.pkg xml2} to preserve axes and calibration.",
              class = "capability", code = "CAPABILITY_UNAVAILABLE", call = call)
  }
  files <- .persisted_source_files(c(image = path))
  .read_telemetry_add(native_metadata_calls = 1, native_file_bytes = NA_real_)
  meta <- RBioFormats::read.metadata(path)
  records <- RBioFormats::coreMetadata(meta)
  if (!is.null(records$sizeX)) records <- list(records)
  available_series <- unique(vapply(records, function(x) as.integer(x$series), integer(1)))
  if (is.null(series)) {
    if (length(available_series) != 1L) {
      .at_abort("Multiple OME image series require explicit {.arg series} selection.",
                code = "OME_SERIES_REQUIRED", call = call)
    }
    series <- available_series[1]
  }
  if (!is.numeric(series) || length(series) != 1L || is.na(series) || !series %in% available_series) {
    .at_abort("Invalid OME series selection.", code = "OME_SERIES_INVALID", call = call)
  }
  records <- Filter(function(x) x$series == series, records)
  records <- unname(records[order(vapply(records, function(x) as.integer(x$resolutionLevel), integer(1)))])
  if (any(vapply(records, function(x) x$sizeZ != 1L || x$sizeT != 1L, logical(1)))) {
    .at_abort("OME Z/time axes are unsupported; select/export a single Z and time plane explicitly.",
              code = "OME_AXES_UNSUPPORTED", call = call)
  }
  nb <- records[[1]]$sizeC
  dtype <- records[[1]]$pixelType
  if (any(vapply(records, function(x) x$sizeC != nb || x$pixelType != dtype, logical(1)))) {
    .at_abort("Inconsistent OME resolution channel/sample metadata.", code = "OME_INCONSISTENT",
              call = call)
  }
  level_dims <- lapply(records, function(x) as.integer(c(x$sizeX, x$sizeY)))
  .read_telemetry_add(native_metadata_calls = 1, native_file_bytes = NA_real_)
  doc <- xml2::read_xml(RBioFormats::read.omexml(path))
  if (!identical(files, .persisted_source_files(c(image = path)))) {
    .at_abort("Image source {.path {basename(path)}} changed during metadata open.",
              class = "io", code = "SOURCE_CHANGED", call = call)
  }
  images <- xml2::xml_find_all(doc, "/*[local-name()='OME']/*[local-name()='Image']")
  if (series > length(images)) {
    .at_abort("OME XML has no metadata for the selected series.", code = "OME_INCONSISTENT",
              call = call)
  }
  pixels <- xml2::xml_find_first(images[[series]], "./*[local-name()='Pixels']")
  channels <- xml2::xml_find_all(pixels, "./*[local-name()='Channel']")
  names <- xml2::xml_attr(channels, "Name")
  bn <- if (length(names) == nb) names else rep(NA_character_, nb)
  values <- suppressWarnings(as.numeric(xml2::xml_attr(channels, "EmissionWavelength")))
  units <- xml2::xml_attr(channels, "EmissionWavelengthUnit")
  wavelengths <- NULL
  wavelength_unit <- NULL
  wavelength_status <- "missing"
  if (length(values) == nb && all(is.finite(values) & values > 0) && !anyNA(units) &&
      length(unique(units)) == 1L) {
    wavelengths <- values
    wavelength_unit <- units[1]
    wavelength_status <- "declared"
  }
  # xml_attr takes a single attribute name; collect the two axes explicitly.
  physical <- vapply(c("PhysicalSizeX", "PhysicalSizeY"), function(k) {
    suppressWarnings(as.numeric(xml2::xml_attr(pixels, k)))
  }, numeric(1))
  physical_units <- vapply(c("PhysicalSizeXUnit", "PhysicalSizeYUnit"), function(k) {
    xml2::xml_attr(pixels, k)
  }, character(1))
  pixel_size <- c(1, 1)
  pixel_unit <- "px"
  calibration_status <- "missing"
  if (all(is.finite(physical) & physical > 0) && !anyNA(physical_units) &&
      length(unique(physical_units)) == 1L) {
    pixel_size <- unname(physical)
    pixel_unit <- unname(physical_units[1])
    calibration_status <- "declared"
  }
  new_annot_image(
    source = path, backend = "ometiff", dims = level_dims[[1]],
    n_levels = length(records), level_dims = level_dims, n_bands = nb, band_names = bn,
    wavelengths = wavelengths, wavelength_unit = wavelength_unit,
    pixel_size = pixel_size, pixel_unit = pixel_unit, dtype = dtype,
    handle = list(windowed = TRUE, path = path, series = series, layout = records, files = files),
    meta = list(capabilities = .window_capabilities("native"),
                reader_contract = list(axes = "yxb", samples = "raw-scalar-v1"),
                series = as.integer(series), calibration_status = calibration_status,
                wavelength_status = wavelength_status, window_read = TRUE)
  )
}

.ometiff_tile <- function(img, level, xrange, yrange, bands) {
  if (isTRUE(img[["handle"]][["windowed"]])) {
    return(.ome_window(img, level, xrange, yrange, bands))
  }
  arr <- img$handle$levels[[level + 1L]]
  ys <- yrange[1]:yrange[2]
  xs <- xrange[1]:xrange[2]
  bs <- if (is.null(bands)) seq_len(img$n_bands) else bands
  arr[ys, xs, bs, drop = FALSE]
}

.ometiff_detect <- function(path) {
  grepl("\\.(ome\\.tif|ome\\.tiff|qptiff)$", path, ignore.case = TRUE)
}

.ometiff_available <- function() {
  requireNamespace("RBioFormats", quietly = TRUE) && requireNamespace("xml2", quietly = TRUE)
}
