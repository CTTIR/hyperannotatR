# ENVI backend: a .hdr text header plus a binary data file. Pure base R (no
# optional dependencies), so it doubles as the reference implementation for
# spectral cube handling and the substrate for spectral example data.
#
# The header and payload are validated together before anything is allocated:
# samples/lines/bands, interleave, data type, byte order, header offset and the
# payload length. Reads are windowed: a tile request seeks to the rows it needs
# and reads only those bytes, so opening or printing a cube never loads it.
#
# Tiles hold the stored values. `data ignore value`, `reflectance scale
# factor` and `data gain/offset values` are recorded in the image metadata
# (`nodata`, `scale_factor`, `data_gain_values`, `data_offset_values`) but are
# never applied to pixels: nodata samples come back as their stored value and
# scaling is left to the caller.

# Map an ENVI "data type" code to readBin parameters.
.envi_dtype <- function(code, call = rlang::caller_env()) {
  switch(
    as.character(code),
    "1"  = list(what = "integer", size = 1L, signed = FALSE, dtype = "uint8"),
    "2"  = list(what = "integer", size = 2L, signed = TRUE,  dtype = "int16"),
    "3"  = list(what = "integer", size = 4L, signed = TRUE,  dtype = "int32"),
    "4"  = list(what = "double",  size = 4L, signed = TRUE,  dtype = "float32"),
    "5"  = list(what = "double",  size = 8L, signed = TRUE,  dtype = "float64"),
    "12" = list(what = "integer", size = 2L, signed = FALSE, dtype = "uint16"),
    "13" = list(what = "integer", size = 4L, signed = FALSE, dtype = "uint32"),
    .at_abort(
      c("Unsupported ENVI data type code {.val {code}}.",
        "i" = "Supported codes: 1 (uint8), 2 (int16), 3 (int32), 4 (float32), 5 (float64), 12 (uint16), 13 (uint32).",
        "x" = "64-bit integer and complex types cannot be represented without loss."),
      code = "ENVI_DTYPE_UNSUPPORTED", call = call
    )
  )
}

# Locate the .hdr and binary data file given either.
.envi_paths <- function(path) {
  if (grepl("\\.hdr$", path, ignore.case = TRUE)) {
    hdr <- path
    base <- sub("\\.hdr$", "", path, ignore.case = TRUE)
    cand <- c(base, paste0(base, c(".dat", ".img", ".raw", ".bin", ".bsq", ".bil", ".bip")))
    dat <- cand[file.exists(cand) & !dir.exists(cand)]
    dat <- if (length(dat)) dat[1] else NA_character_
  } else {
    dat <- path
    hdr <- paste0(path, ".hdr")
    if (!file.exists(hdr)) {
      hdr <- sub("\\.[^.]+$", ".hdr", path)
    }
  }
  list(hdr = hdr, dat = dat)
}

# Extract a single ENVI header field (scalar or brace list) as a trimmed string.
.envi_field <- function(txt, key) {
  key_pat <- gsub(" ", "[ \\t]+", key)
  brace <- paste0("(?im)^[ \\t]*", key_pat, "[ \\t]*=[ \\t]*\\{([^}]*)\\}")
  m <- regexpr(brace, txt, perl = TRUE)
  if (m != -1L) {
    val <- regmatches(txt, m)
    return(trimws(sub(brace, "\\1", val, perl = TRUE)))
  }
  scal <- paste0("(?im)^[ \\t]*", key_pat, "[ \\t]*=[ \\t]*(.*)$")
  m <- regexpr(scal, txt, perl = TRUE)
  if (m == -1L) {
    return(NULL)
  }
  val <- regmatches(txt, m)
  trimws(sub(scal, "\\1", val, perl = TRUE))
}

# Parse a whole non-negative integer header value; abort when malformed.
.envi_count <- function(txt, key, hdr, required = TRUE, min = 1, default = NULL,
                        call = rlang::caller_env()) {
  v <- .envi_field(txt, key)
  if (is.null(v)) {
    if (required) {
      .at_abort("ENVI header {.file {basename(hdr)}} is missing {.field {key}}.",
                code = "ENVI_HEADER_INVALID", call = call)
    }
    return(default)
  }
  num <- suppressWarnings(as.numeric(v))
  if (length(num) != 1L || is.na(num) || num != round(num) || num < min || num > .Machine$integer.max) {
    .at_abort("ENVI header field {.field {key}} must be a whole number >= {min}; got {.val {v}}.",
              code = "ENVI_HEADER_INVALID", call = call)
  }
  as.integer(num)
}

# Parse a brace list of numbers; returns NULL when absent. Non-numeric entries
# become NA so they are reported, never silently dropped.
.envi_num_list <- function(txt, key) {
  v <- .envi_field(txt, key)
  if (is.null(v)) {
    return(NULL)
  }
  suppressWarnings(as.numeric(trimws(strsplit(v, ",")[[1]])))
}

# Parse and validate the ENVI header into a list. The header is metadata, so
# it is bounded (1 MiB) and read exactly once.
.parse_envi_hdr <- function(hdr, call = rlang::caller_env()) {
  size <- file.info(hdr)$size
  if (!is.finite(size) || size > 1024^2) {
    .at_abort("ENVI header {.file {basename(hdr)}} exceeds the 1 MiB metadata limit.",
              class = "limit", code = "ENVI_HEADER_INVALID", call = call)
  }
  con <- file(hdr, "rb")
  on.exit(close(con), add = TRUE)
  raw <- .window_read_raw(con, size, call = call)
  raw <- raw[raw != as.raw(0L)]
  lines_txt <- strsplit(sub("\r?\n$", "", gsub("\r\n?", "\n", rawToChar(raw))), "\n",
                        fixed = FALSE)[[1]]
  if (length(lines_txt) == 0L || !grepl("^\\s*ENVI\\s*$", lines_txt[1])) {
    .at_abort("{.file {basename(hdr)}} does not start with the {.val ENVI} magic line.",
              code = "ENVI_HEADER_INVALID", call = call)
  }
  txt <- paste(lines_txt, collapse = "\n")
  samples <- .envi_count(txt, "samples", hdr, call = call)
  lines <- .envi_count(txt, "lines", hdr, call = call)
  bands <- .envi_count(txt, "bands", hdr, call = call)
  header_offset <- .envi_count(txt, "header offset", hdr, required = FALSE, min = 0,
                               default = 0L, call = call)
  # ENVI requires `data type`; guessing a width would decode garbage.
  data_type <- .envi_count(txt, "data type", hdr, call = call)
  byte_order <- .envi_count(txt, "byte order", hdr, required = FALSE, min = 0,
                            default = 0L, call = call)
  if (byte_order > 1L) {
    .at_abort("ENVI {.field byte order} must be 0 (little endian) or 1 (big endian).",
              code = "ENVI_HEADER_INVALID", call = call)
  }
  interleave <- tolower(.envi_field(txt, "interleave") %||% "bsq")
  if (!interleave %in% c("bsq", "bil", "bip")) {
    .at_abort("Unsupported ENVI interleave {.val {interleave}}.",
              code = "ENVI_HEADER_INVALID", call = call)
  }
  wl <- .envi_num_list(txt, "wavelength")
  fwhm <- .envi_num_list(txt, "fwhm")
  bn <- .envi_field(txt, "band names")
  bn <- if (is.null(bn)) NULL else trimws(strsplit(bn, ",")[[1]])
  ignore <- suppressWarnings(as.numeric(.envi_field(txt, "data ignore value")))
  refl_scale <- suppressWarnings(as.numeric(.envi_field(txt, "reflectance scale factor")))
  gain <- .envi_num_list(txt, "data gain values")
  offs <- .envi_num_list(txt, "data offset values")
  issues <- character()
  if (!is.null(wl) && length(wl) != bands) {
    issues <- c(issues, sprintf("wavelength count %d does not match bands %d", length(wl), bands))
  }
  if (!is.null(fwhm) && length(fwhm) != bands) {
    issues <- c(issues, sprintf("fwhm count %d does not match bands %d", length(fwhm), bands))
    fwhm <- NULL
  }
  if (!is.null(bn) && length(bn) != bands) {
    issues <- c(issues, sprintf("band names count %d does not match bands %d", length(bn), bands))
    bn <- NULL
  }
  list(
    samples = samples, lines = lines, bands = bands, interleave = interleave,
    endian = if (byte_order == 1L) "big" else "little",
    byte_order = byte_order, data_type = data_type, header_offset = header_offset,
    wavelengths = wl, wavelength_units = .envi_field(txt, "wavelength units"),
    fwhm = fwhm, band_names = bn,
    data_ignore_value = if (length(ignore) == 1L && !is.na(ignore)) ignore else NULL,
    reflectance_scale_factor = if (length(refl_scale) == 1L && !is.na(refl_scale)) refl_scale else NULL,
    data_gain_values = gain, data_offset_values = offs,
    sensor_type = .envi_field(txt, "sensor type"),
    issues = issues
  )
}

# Validate the payload length against the header before any read.
.envi_check_payload <- function(dat, h, spec, call = rlang::caller_env()) {
  expected <- h$header_offset + as.double(h$samples) * h$lines * h$bands * spec$size
  size <- file.info(dat)$size
  if (is.na(size) || size < expected) {
    .at_abort(
      c("The ENVI payload {.file {basename(dat)}} is shorter than its header declares.",
        "x" = "Expected at least {format(expected, big.mark = ',')} bytes; found {format(size %||% NA, big.mark = ',')}."),
      code = "PAYLOAD_SHORT", details = list(expected_bytes = expected, actual_bytes = size),
      call = call
    )
  }
  size - expected
}

# Read `n` values at byte `offset` from an open connection. Integers are
# decoded exactly (int32 INT_MIN and uint32 values above 2^31 are valid
# samples, not missing data); the result is always double.
.envi_read_at <- function(con, offset, n, spec, endian) {
  seek(con, where = offset, origin = "start", rw = "read")
  raw <- .window_read_raw(con, n * spec$size)
  if (spec$what == "integer") {
    return(.decode_integer_bytes(raw, spec$size, spec$signed, endian))
  }
  readBin(raw, what = "double", n = n, size = spec$size, endian = endian)
}

# Windowed read of rows y1..y2, columns x1..x2 (1-based, inclusive) and the
# given bands, in request order and possibly repeated, into a [y, x, band]
# double array. Each distinct band is read once.
.envi_read_window <- function(dat, h, xrange, yrange, bands, chunk_values = 2^24) {
  .window_budget(xrange[2] - xrange[1] + 1, yrange[2] - yrange[1] + 1, length(bands))
  distinct <- sort(unique(bands))
  out <- .envi_read_distinct(dat, h, xrange, yrange, distinct, chunk_values)
  fb <- attr(out, "file_bytes")
  out <- out[, , match(bands, distinct), drop = FALSE]
  attr(out, "file_bytes") <- fb
  .read_telemetry_add(decoded_bytes = 8 * length(out))
  out
}

# Read sorted distinct `bands`. A full-width window is read as contiguous
# blocks (one per band for BSQ, chunks of rows for BIL/BIP); a partial width
# seeks to each row.
.envi_read_distinct <- function(dat, h, xrange, yrange, bands, chunk_values = 2^24) {
  spec <- .envi_dtype(h$data_type)
  sz <- spec$size
  nx <- xrange[2] - xrange[1] + 1L
  ny <- yrange[2] - yrange[1] + 1L
  out <- array(NA_real_, dim = c(ny, nx, length(bands)))
  con <- file(dat, "rb")
  on.exit(close(con), add = TRUE)
  S <- as.double(h$samples)
  L <- as.double(h$lines)
  B <- as.double(h$bands)
  x0 <- xrange[1] - 1
  y0 <- yrange[1] - 1
  full <- nx == h$samples
  if (full && h$interleave == "bsq") {
    for (ib in seq_along(bands)) {
      off <- h$header_offset + ((bands[ib] - 1) * L + y0) * S * sz
      v <- .envi_read_at(con, off, ny * nx, spec, h$endian)
      out[, , ib] <- matrix(v, nrow = ny, ncol = nx, byrow = TRUE)
    }
    attr(out, "file_bytes") <- ny * nx * length(bands) * sz
    return(out)
  }
  if (full && (h$interleave == "bip" || 2 * length(bands) >= h$bands)) {
    # BIL rows hold [band, x]; BIP rows hold [x, band]. Either way the window
    # is ny consecutive rows of S * B values, read in chunks of rows so the
    # transient buffer stays bounded.
    per_row <- S * B
    chunk <- max(1, floor(chunk_values / per_row))
    done <- 0
    while (done < ny) {
      k <- min(chunk, ny - done)
      v <- .envi_read_at(con, h$header_offset + (y0 + done) * per_row * sz,
                         k * per_row, spec, h$endian)
      a <- if (h$interleave == "bil") {
        array(v, dim = c(nx, h$bands, k)) # [x, band, y]
      } else {
        aperm(array(v, dim = c(h$bands, nx, k)), c(2, 1, 3)) # -> [x, band, y]
      }
      out[done + seq_len(k), , ] <- aperm(a[, bands, , drop = FALSE], c(3, 1, 2))
      done <- done + k
    }
    attr(out, "file_bytes") <- ny * nx * as.double(h$bands) * sz
    return(out)
  }
  for (iy in seq_len(ny)) {
    y <- y0 + iy - 1
    if (h$interleave == "bip") {
      off <- h$header_offset + ((y * S + x0) * B) * sz
      v <- .envi_read_at(con, off, nx * h$bands, spec, h$endian)
      m <- matrix(v, nrow = h$bands)
      out[iy, , ] <- t(m[bands, , drop = FALSE])
    } else {
      for (ib in seq_along(bands)) {
        b <- bands[ib] - 1
        off <- if (h$interleave == "bsq") {
          h$header_offset + ((b * L + y) * S + x0) * sz
        } else {
          h$header_offset + ((y * B + b) * S + x0) * sz
        }
        out[iy, , ib] <- .envi_read_at(con, off, nx, spec, h$endian)
      }
    }
  }
  attr(out, "file_bytes") <- if (h$interleave == "bip") {
    ny * nx * as.double(h$bands) * sz
  } else {
    ny * nx * length(bands) * sz
  }
  out
}

# Eager whole-cube read, kept for callers that construct handles directly.
.read_envi_data <- function(dat, h) {
  arr <- .envi_read_window(dat, h, c(1L, h$samples), c(1L, h$lines), seq_len(h$bands))
  attr(arr, "file_bytes") <- NULL
  arr
}

.envi_read <- function(path, value_unit = NULL, ..., call = rlang::caller_env()) {
  p <- .envi_paths(path)
  if (is.na(p$dat) || !file.exists(p$dat)) {
    .at_abort(c(
      "Could not find the ENVI binary data file for {.path {path}}.",
      "i" = "Expected a data file alongside the {.file .hdr} header."
    ), class = "io", code = "FILE_MISSING", call = call)
  }
  if (!file.exists(p$hdr)) {
    .at_abort("Could not find the ENVI header for {.path {path}}.", class = "io",
              code = "FILE_MISSING", call = call)
  }
  files <- .persisted_source_files(c(header = p$hdr, payload = p$dat))
  h <- .parse_envi_hdr(p$hdr, call = call)
  spec <- .envi_dtype(h$data_type, call = call)
  trailing <- .envi_check_payload(p$dat, h, spec, call = call)
  if (!identical(files, .persisted_source_files(c(header = p$hdr, payload = p$dat)))) {
    .at_abort("Image source {.path {basename(path)}} changed during metadata open.",
              class = "io", code = "SOURCE_CHANGED", call = call)
  }
  bn <- h$band_names %||% NA_character_
  wl <- h$wavelengths
  # Undeclared wavelength units stay unknown; they are never assumed.
  unit <- if (is.null(wl)) NULL else h$wavelength_units
  if (!is.null(unit) && tolower(unit) %in% c("nanometers", "nanometer", "nm")) unit <- "nm"
  if (!is.null(unit) && tolower(unit) %in% c("micrometers", "micrometer", "um", "microns")) {
    unit <- "um"
  }
  meta <- list(
    format = "ENVI", interleave = h$interleave, byte_order = h$endian,
    header_bytes = h$header_offset, trailing_bytes = trailing,
    axis_order = "y,x,band", data_type_code = h$data_type,
    fwhm = h$fwhm, nodata = h$data_ignore_value %||% NA_real_,
    scale_factor = h$reflectance_scale_factor %||% NA_real_,
    data_gain_values = h$data_gain_values, data_offset_values = h$data_offset_values,
    offset = NA_real_, instrument = h$sensor_type %||% NA_character_,
    value_unit = value_unit %||% "unknown", header_issues = h$issues,
    window_read = TRUE,
    reader_contract = list(axes = "yxb", samples = "raw-scalar-v1"),
    capabilities = .window_capabilities("binary"),
    calibration = list(status = if (!is.null(h$reflectance_scale_factor) ||
                                    !is.null(h$data_gain_values)) "declared" else "missing")
  )
  meta$calibration_digest <- if (identical(meta$calibration$status, "declared")) {
    .digest_json(list(reflectance_scale_factor = h$reflectance_scale_factor,
                      data_gain_values = as.list(h$data_gain_values),
                      data_offset_values = as.list(h$data_offset_values)))
  } else {
    NA_character_
  }
  new_annot_image(
    source = path, backend = "envi",
    dims = c(h$samples, h$lines), n_levels = 1L,
    level_dims = list(c(h$samples, h$lines)),
    n_bands = h$bands, band_names = bn,
    wavelengths = wl, wavelength_unit = unit,
    pixel_size = c(1, 1), pixel_unit = "px", dtype = spec$dtype,
    handle = list(dat = normalizePath(p$dat), header = h, files = files),
    meta = meta
  )
}

.envi_tile <- function(img, level, xrange, yrange, bands) {
  bs <- if (is.null(bands)) seq_len(img$n_bands) else bands
  arr <- img$handle$data
  if (!is.null(arr)) {
    return(arr[yrange[1]:yrange[2], xrange[1]:xrange[2], bs, drop = FALSE])
  }
  h <- img$handle$header
  if (is.null(h) || is.null(img$handle$dat)) {
    .at_abort(
      c("This image handle has no pixel access (it was saved without its reader state).",
        "i" = "Re-open the source with {.fn at_read_image}."),
      class = "io", code = "IMAGE_UNAVAILABLE"
    )
  }
  .envi_read_window(img$handle$dat, h, xrange, yrange, bs)
}

.envi_detect <- function(path) {
  if (grepl("\\.hdr$", path, ignore.case = TRUE)) {
    return(TRUE)
  }
  # A data file with a sibling .hdr.
  hdr <- .envi_paths(path)$hdr
  file.exists(hdr) && grepl("\\.(dat|img|raw|bin|bsq|bil|bip)$", path, ignore.case = TRUE)
}

.envi_available <- function() TRUE
