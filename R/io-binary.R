# Validated binary layouts shared by the NPY, ENVI and SpecCube readers: byte
# budgets, payload-length checks before any read, and exact integer decoding.

# Abort when a read would exceed the byte budget, option hyperannotatR.max_read_bytes
# (default 1 GiB).
.read_budget <- function(bytes, call = rlang::caller_env()) {
  limit <- getOption("hyperannotatR.max_read_bytes", 1024^3)
  if (!is.numeric(limit) || length(limit) != 1L || !is.finite(limit) || limit <= 0) {
    .at_abort("Option {.code hyperannotatR.max_read_bytes} must be a positive finite byte limit.",
              call = call)
  }
  if (!is.finite(bytes) || bytes > limit) {
    .at_abort(
      c("Requested read exceeds the byte budget/limit ({format(limit, big.mark = ',')} bytes).",
        "i" = "Raise {.code options(hyperannotatR.max_read_bytes = )} for a trusted large file."),
      class = "limit", code = "READ_BUDGET_EXCEEDED",
      details = list(requested_bytes = bytes, limit_bytes = limit), call = call
    )
  }
  invisible(bytes)
}

# Validate the dimensions, element size and offset of a binary payload against
# the file before anything is allocated. With `eager = TRUE` the whole array
# must also fit R's indexing and the read budget.
.binary_layout <- function(path, dims, size, offset = 0, eager = TRUE,
                           call = rlang::caller_env()) {
  if (!is.numeric(dims) || !length(dims) || any(!is.finite(dims)) ||
      any(dims < 1 | dims != trunc(dims) | dims > .Machine$integer.max)) {
    .at_abort("Image/mask dimensions must be positive representable integers; zero-sized arrays are unsupported.",
              code = "LAYOUT_INVALID", call = call)
  }
  if (length(offset) != 1L || !is.finite(offset) || offset < 0 || offset != trunc(offset) ||
      offset > 2^53 - 1) {
    .at_abort("Invalid binary header offset; expected a nonnegative exact integer.",
              code = "LAYOUT_INVALID", call = call)
  }
  count <- prod(as.double(dims))
  bytes <- count * size
  if (!is.finite(bytes) || count > 2^53 - 1 || bytes > 2^53 - 1 - offset) {
    .at_abort("Binary dimensions/payload size exceed supported resource limits.",
              class = "limit", code = "LAYOUT_TOO_LARGE", call = call)
  }
  if (eager) {
    if (count > .Machine$integer.max) {
      .at_abort("Eager array exceeds integer indexing limits.", class = "limit",
                code = "LAYOUT_TOO_LARGE", call = call)
    }
    .read_budget(max(bytes, count * 8), call = call)
  }
  actual <- file.info(path)$size
  if (length(actual) != 1L || !is.finite(actual) || actual < offset + bytes) {
    .at_abort(
      "Short/truncated binary payload: expected at least {format(offset + bytes, scientific = FALSE)} bytes.",
      class = "io", code = "PAYLOAD_SHORT",
      details = list(expected_bytes = offset + bytes, actual_bytes = actual), call = call
    )
  }
  list(dims = as.integer(dims), count = count, size = size, offset = offset, bytes = bytes)
}

.read_exact_raw <- function(con, n, call = rlang::caller_env()) {
  x <- readBin(con, "raw", n = n)
  if (length(x) != n) {
    .at_abort("Short/truncated binary payload or header.", class = "io",
              code = "PAYLOAD_SHORT", call = call)
  }
  x
}

# Decode little/big-endian integer bytes exactly. readBin(what = "integer",
# size = 4) maps the INT_MIN bit pattern to NA, but -2147483648 is a valid
# quantitative image sample (and 2^31 a valid uint32), so 4-byte values are
# repaired from that single pattern and image values come back as exact
# doubles. 1- and 2-byte values are exact through readBin. 64-bit values are
# accepted only when they fit the 32-bit range. With `mask = TRUE` the values
# must fit R integers (INT_MIN stays reserved for NA) and come back as integer.
.decode_integer_bytes <- function(bytes, size, signed, endian, mask = FALSE,
                                  call = rlang::caller_env()) {
  if (!size %in% c(1L, 2L, 4L, 8L) || length(bytes) %% size != 0) {
    .at_abort("Unsupported integer encoding or short payload.", class = "io",
              code = "PAYLOAD_INVALID", call = call)
  }
  out_of_range <- function() {
    .at_abort("Integer samples are outside the finite representable mask range.",
              class = "io", code = "VALUE_OUT_OF_RANGE", call = call)
  }
  # 32-bit words as exact unsigned doubles.
  unsigned_words <- function(n) {
    w <- readBin(bytes, "integer", n = n, size = 4L, endian = endian)
    u <- as.double(w)
    u[is.na(w)] <- 2147483648
    u[u < 0] <- u[u < 0] + 4294967296
    u
  }
  n <- length(bytes) %/% size
  if (size <= 2L) {
    low <- as.double(readBin(bytes, "integer", n = n, size = size, signed = signed,
                             endian = endian))
  } else if (size == 4L) {
    low <- unsigned_words(n)
    if (signed) low[low >= 2147483648] <- low[low >= 2147483648] - 4294967296
  } else {
    u <- unsigned_words(2 * n)
    first <- u[c(TRUE, FALSE)]
    second <- u[c(FALSE, TRUE)]
    low <- if (endian == "big") second else first
    high <- if (endian == "big") first else second
    negative <- signed & high == 4294967295 & low > 2147483648
    positive <- high == 0 & low <= .Machine$integer.max
    if (any(!(negative | positive))) out_of_range()
    low[negative] <- low[negative] - 4294967296
  }
  if (mask) {
    if (any(abs(low) > .Machine$integer.max)) out_of_range()
    low <- as.integer(low)
  }
  low
}
