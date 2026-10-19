# Abort for an invalid argument: a classified validation error attributed to the
# user-facing caller. `.envir` is the validator's frame so its variables
# interpolate into the message.
.check_abort <- function(message, call, .envir = parent.frame()) {
  cli::cli_abort(message, class = c("at_validation_error", "at_error"),
                 code = "VALIDATION_FAILED", call = call, .envir = .envir)
}

# Internal input validators. Each accepts `arg` (the caller's argument name)
# and `call` (the caller's environment) so that errors are attributed to the
# user-facing function, not to the validator. None are exported.
#
# Every validator returns its (coerced) input invisibly on success and aborts
# via `.check_abort()` on failure.

# A single non-missing string.
.check_string <- function(x,
                          allow_null = FALSE,
                          arg = rlang::caller_arg(x),
                          call = rlang::caller_env()) {
  if (allow_null && is.null(x)) {
    return(invisible(x))
  }
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    .check_abort(
      c(
        "{.arg {arg}} must be a single string.",
        "x" = "You supplied {.cls {class(x)[1]}} of length {length(x)}."
      ),
      call = call
    )
  }
  invisible(x)
}

# A single non-missing TRUE/FALSE.
.check_flag <- function(x,
                        arg = rlang::caller_arg(x),
                        call = rlang::caller_env()) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    .check_abort(
      c(
        "{.arg {arg}} must be a single {.code TRUE} or {.code FALSE}.",
        "x" = "You supplied {.cls {class(x)[1]}} of length {length(x)}."
      ),
      call = call
    )
  }
  invisible(x)
}

# A single finite number, optionally bounded.
.check_number <- function(x,
                          min = -Inf,
                          max = Inf,
                          allow_null = FALSE,
                          arg = rlang::caller_arg(x),
                          call = rlang::caller_env()) {
  if (allow_null && is.null(x)) {
    return(invisible(x))
  }
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x)) {
    .check_abort(
      c(
        "{.arg {arg}} must be a single finite number.",
        "x" = "You supplied {.cls {class(x)[1]}} of length {length(x)}."
      ),
      call = call
    )
  }
  if (x < min || x > max) {
    .check_abort(
      c(
        "{.arg {arg}} must be in the range [{min}, {max}].",
        "x" = "You supplied {.val {x}}."
      ),
      call = call
    )
  }
  invisible(as.numeric(x))
}

# A single non-negative whole number (a count). Returns an integer.
.check_count <- function(x,
                         min = 0L,
                         arg = rlang::caller_arg(x),
                         call = rlang::caller_env()) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x != round(x)) {
    .check_abort(
      c(
        "{.arg {arg}} must be a single whole number.",
        "x" = "You supplied {.cls {class(x)[1]}} of length {length(x)}."
      ),
      call = call
    )
  }
  if (abs(x) > .Machine$integer.max) {
    .check_abort(
      c(
        "{.arg {arg}} is too large.",
        "x" = "You supplied {.val {x}}; the maximum is {.val {(.Machine$integer.max)}}."
      ),
      call = call
    )
  }
  xi <- as.integer(round(x))
  if (xi < min) {
    .check_abort(
      c(
        "{.arg {arg}} must be at least {min}.",
        "x" = "You supplied {.val {xi}}."
      ),
      call = call
    )
  }
  invisible(xi)
}

# An existing file.
.check_file <- function(x,
                        arg = rlang::caller_arg(x),
                        call = rlang::caller_env()) {
  .check_string(x, arg = arg, call = call)
  if (!file.exists(x) || dir.exists(x)) {
    .check_abort(
      c(
        "{.arg {arg}} must be an existing file.",
        "x" = "{.path {x}} does not exist.",
        "i" = "Use {.fn at_example_path} to locate the bundled sample data."
      ),
      call = call
    )
  }
  invisible(x)
}

# An existing directory.
.check_dir <- function(x,
                       arg = rlang::caller_arg(x),
                       call = rlang::caller_env()) {
  .check_string(x, arg = arg, call = call)
  if (!dir.exists(x)) {
    .check_abort(
      c(
        "{.arg {arg}} must be an existing directory.",
        "x" = "{.path {x}} does not exist or is not a directory."
      ),
      call = call
    )
  }
  invisible(x)
}

# `x` must inherit from S3 class `cls`.
.check_class <- function(x,
                         cls,
                         allow_null = FALSE,
                         arg = rlang::caller_arg(x),
                         call = rlang::caller_env()) {
  if (allow_null && is.null(x)) {
    return(invisible(x))
  }
  if (!inherits(x, cls)) {
    .check_abort(
      c(
        "{.arg {arg}} must be a {.cls {cls}} object.",
        "x" = "You supplied {.cls {class(x)[1]}}."
      ),
      call = call
    )
  }
  invisible(x)
}

# Exact scalar choices: a single non-missing string, or for numeric choices a
# single finite whole number of any numeric type (8 and 8L both match 8L; the
# matching choice is returned). An explicitly supplied vector is invalid even
# when it equals the choices. Only an omitted `c(...)` default stands for its
# first element: callers may say so with `default = missing(arg)`; otherwise
# omission of the caller's argument is detected in the caller's frame with the
# same semantics as `missing()`.
.check_choice <- function(x, choices,
                          arg = rlang::caller_arg(x),
                          call = rlang::caller_env(), default = NULL) {
  if (is.null(default)) {
    default <- .arg_omitted(substitute(x), parent.frame())
  }
  if (isTRUE(default) && length(x) > 1L && !anyNA(x) && length(x) == length(choices) &&
      !anyDuplicated(x) && all(x %in% choices)) {
    return(choices[[match(x[[1]], choices)]])
  }
  valid <- if (is.numeric(choices)) {
    is.numeric(x) && !is.complex(x) && length(x) == 1L &&
      !is.na(x) && is.finite(x) && x == trunc(x) && x %in% choices
  } else {
    is.character(x) && length(x) == 1L && !is.na(x) && x %in% choices
  }
  if (!valid) {
    supplied <- if (length(x) == 0L) {
      "You supplied a length-0 value."
    } else if (length(x) > 1L) {
      paste0("You supplied ", length(x), " values; explicit vectors are not defaults.")
    } else {
      paste0("You supplied ", format(x), ".")
    }
    .check_abort(
      c("{.arg {arg}} must be one of {.or {.val {choices}}}.",
        "x" = "{supplied}",
        "i" = "Supply a single non-missing {if (is.numeric(choices)) 'finite whole number' else 'string'}."),
      call = call
    )
  }
  if (is.numeric(choices)) choices[[match(x, choices)]] else x
}

# Was `expr` (a caller's argument, passed on as a bare symbol) omitted by the
# caller's caller? Equivalent to calling `missing()` inside the caller; FALSE
# for anything that is not one of the caller's formal arguments.
.arg_omitted <- function(expr, env) {
  if (!is.symbol(expr)) return(FALSE)
  isTRUE(tryCatch(eval(call("missing", expr), env), error = function(e) FALSE))
}

# Domain-object validators.

.check_image <- function(x,
                         arg = rlang::caller_arg(x),
                         call = rlang::caller_env()) {
  .check_class(x, "annot_image", arg = arg, call = call)
}

.check_roi <- function(x,
                       arg = rlang::caller_arg(x),
                       call = rlang::caller_env()) {
  .check_class(x, "annot_roi", arg = arg, call = call)
}

.check_layer <- function(x,
                         arg = rlang::caller_arg(x),
                         call = rlang::caller_env()) {
  .check_class(x, "annot_layer", arg = arg, call = call)
}

.check_project <- function(x,
                           arg = rlang::caller_arg(x),
                           call = rlang::caller_env()) {
  .check_class(x, "annot_project", arg = arg, call = call)
}
