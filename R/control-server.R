# Loopback control service lifecycle: start, stop and close. The service binds
# to 127.0.0.1 only, authenticates with a random short-lived bearer token, and
# writes a sanitised lifecycle manifest (no token, no root, no image paths).
# It only ever stops itself; it never terminates another process.

.control_write_manifest <- function(hub, state, reason = NA_character_) {
  doc <- list(
    document = "annotatr_control_manifest",
    protocol = hub$protocol,
    protocol_version = hub$protocol_version,
    annotatr_version = .pkg_version(),
    instance_id = hub$instance_id,
    session_id = hub$session_id,
    state = state,
    host = hub$host,
    port = hub$port,
    pid = hub$pid,
    started_at = .utc_stamp(hub$created),
    expires_at = .utc_stamp(hub$expires_at),
    stopped_at = if (state %in% c("stopped", "expired")) .utc_stamp() else NA_character_,
    stop_reason = reason,
    final_state_revision = if (state %in% c("stopped", "expired")) as.character(hub$revision) else NA_character_,
    requests_recorded = length(hub$request_order),
    events_emitted = hub$event_seq,
    capability_digest = at_interop_capabilities(target = "control")$digest,
    token = "never stored here; supplied via token_file or the in-process handle"
  )
  .write_json_atomic(doc, hub$manifest_path)
}

# Stop serving and mark the hub stopped. Idempotent.
.control_shutdown <- function(hub, reason = "stopped") {
  if (identical(hub$status, "stopped")) {
    return(invisible(FALSE))
  }
  if (is.function(hub$cancel_expiry)) {
    hub$cancel_expiry()
    hub$cancel_expiry <- NULL
  }
  if (!is.null(hub$server) && requireNamespace("httpuv", quietly = TRUE)) {
    tryCatch(httpuv::stopServer(hub$server), error = function(e) NULL)
  }
  hub$server <- NULL
  final <- if (identical(reason, "ttl expired")) "expired" else "stopped"
  hub$status <- "stopped"
  if (exists(hub$instance_id, envir = .control_tokens, inherits = FALSE)) {
    rm(list = hub$instance_id, envir = .control_tokens)
  }
  if (exists(hub$instance_id, envir = .control_registry, inherits = FALSE)) {
    rm(list = hub$instance_id, envir = .control_registry)
  }
  if (!is.na(hub$manifest_path)) {
    tryCatch(.control_write_manifest(hub, final, reason), error = function(e) NULL)
  }
  invisible(TRUE)
}

# The request headers the dispatcher looks at, from a Rook environment.
.control_rook_headers <- function(req) {
  headers <- list(
    host = req$HTTP_HOST %||% "",
    origin = req$HTTP_ORIGIN %||% "",
    authorization = req$HTTP_AUTHORIZATION %||% "",
    `content-type` = req$CONTENT_TYPE %||% req$HTTP_CONTENT_TYPE %||% "",
    `x-request-id` = req$HTTP_X_REQUEST_ID %||% ""
  )
  headers[nzchar(unlist(headers))]
}

.control_rook_response <- function(res) {
  txt <- jsonlite::toJSON(res$body, auto_unbox = TRUE, null = "null", na = "null",
                          digits = I(17))
  list(status = res$status,
       headers = list(`Content-Type` = "application/json; charset=utf-8",
                      `Cache-Control` = "no-store",
                      `X-Content-Type-Options` = "nosniff"),
       body = as.character(txt))
}

# Checks made as soon as the request headers arrive, before httpuv buffers
# the body: the security gate (Host, Origin, token, TTL) and a declared
# Content-Length above the limit. Returns NULL to continue, or a response.
.control_preflight <- function(hub, req) {
  headers <- .control_rook_headers(req)
  request_id <- .header(headers, "x-request-id") %||% paste0("request-", .uuid())
  tryCatch({
    .control_gate(hub, headers, "http")
    if (identical(req$REQUEST_METHOD, "POST")) {
      len <- suppressWarnings(as.numeric(req$CONTENT_LENGTH %||% req$HTTP_CONTENT_LENGTH %||% NA))
      if (!is.na(len) && len > hub$max_body_bytes) {
        .control_fail("PAYLOAD_TOO_LARGE", "The request body exceeds the size limit.",
                      details = list(limit_bytes = hub$max_body_bytes), class = "limit")
      }
    }
    NULL
  }, error = function(cnd) {
    .control_response(hub, .control_status_for(.condition_code(cnd)), request_id,
                      error = .control_error_body(cnd, hub))
  })
}

# httpuv application: translate Rook requests to the shared dispatcher.
.control_httpuv_app <- function(hub) {
  list(
    onHeaders = function(req) {
      early <- .control_preflight(hub, req)
      if (is.null(early)) NULL else .control_rook_response(early)
    },
    call = function(req) {
      headers <- .control_rook_headers(req)
      len <- suppressWarnings(as.numeric(req$CONTENT_LENGTH %||% "0"))
      body <- raw()
      if (identical(req$REQUEST_METHOD, "POST")) {
        if (!is.na(len) && len > hub$max_body_bytes) {
          body <- as.raw(rep(1L, hub$max_body_bytes + 1L))
        } else if (!is.null(req$rook.input)) {
          body <- req$rook.input$read()
        }
      }
      res <- .control_handle_request(hub, req$REQUEST_METHOD, req$PATH_INFO %||% "/",
                                     req$QUERY_STRING %||% "", headers, body)
      .control_rook_response(res)
    }
  )
}

# Write the token to a new file readable only by its owner. The file is
# created exclusively (an existing file or symbolic link is refused) with a
# 077 umask, so it is never readable by others, even briefly. On Windows file
# modes are not enforced: rely on the directory's ACLs there.
.control_write_token <- function(token, path, call = rlang::caller_env()) {
  exists_already <- file.exists(path) || .is_symlink(path)
  if (exists_already) {
    .at_abort("{.arg token_file} already exists; refusing to overwrite it.", class = "io",
              code = "DESTINATION_EXISTS", call = call)
  }
  if (!dir.exists(dirname(path))) {
    .at_abort("The directory of {.arg token_file} does not exist.", class = "io",
              code = "FILE_MISSING", call = call)
  }
  old <- Sys.umask("077")
  on.exit(Sys.umask(old), add = TRUE)
  con <- tryCatch(file(path, open = "wxb"), error = function(e) NULL, warning = function(w) NULL)
  if (is.null(con)) {
    .at_abort("Could not create {.arg token_file} exclusively.", class = "io",
              code = "DESTINATION_EXISTS", call = call)
  }
  ok <- tryCatch({
    writeBin(charToRaw(paste0(token, "\n")), con)
    TRUE
  }, error = function(e) FALSE, finally = close(con))
  if (!ok) {
    unlink(path)
    .at_abort("Could not write {.arg token_file}.", class = "io", code = "WRITE_FAILED", call = call)
  }
  Sys.chmod(path, mode = "0600", use_umask = FALSE)
  invisible(path)
}

#' Start the local control service
#'
#' Start an `annotatr-control-v1` service for a session so that a partner
#' process (for example qupflowR) can read state and events and send typed
#' commands. Nothing is started unless this function is called with
#' `control = "loopback"`. The service binds only to `127.0.0.1`, requires a
#' random 256-bit bearer token that expires after `ttl_seconds`, rejects
#' browser-origin requests, enforces JSON size and path limits, and resolves
#' file references only below `root`. There is no endpoint that evaluates code.
#'
#' The token is never written into URLs, logs, downloads, manifests or RDS
#' files. In-process calls use the returned handle; a separate client process
#' reads the token from `token_file`, which is created exclusively with
#' owner-only permissions (on Windows, file modes are not enforced; keep the
#' file in a directory only the user can read). A sanitised lifecycle manifest
#' `annotatr-control-<instance_id>.json` is written to `root` at start and
#' rewritten when the service stops.
#'
#' The service stops itself when the token expires: either when the expiry
#' timer runs or, if a request arrives first (for example after the computer
#' slept), on that request. Error messages sent to clients never contain
#' absolute local paths. Request bodies whose declared `Content-Length`
#' exceeds `max_body_bytes`, and requests that fail the Host, Origin or token
#' checks, are refused before the body is read (a chunked body without
#' `Content-Length` is buffered by httpuv and then refused).
#'
#' Two options bound work done for clients: `hyperannotatR.control_mask_max_pixels`
#' (default `4096^2`) is the largest mask `mask.preview` builds (without a
#' `level` it picks the finest pyramid level within the budget), and
#' `hyperannotatR.control_hash_max_bytes` (default 256 MiB) is the largest queue
#' entry whose content id `GET /v1/state` computes before the entry is visited
#' (larger entries report `image_id: null` until then).
#'
#' @param session What to control: an [annot_session] (or anything
#'   [at_annotate()] accepts).
#' @param control Must be `"loopback"`.
#' @param host Must be `"127.0.0.1"`.
#' @param port Port; `0` picks a random free port.
#' @param ttl_seconds Token lifetime in seconds (1 to 86400).
#' @param root Directory for payload references, exports, training exports and
#'   the lifecycle manifest; defaults to `<session out_dir>/control`.
#' @param token_file Optional path of a new file to receive the token (for a
#'   client process). It must not exist yet.
#'
#' The token needs a cryptographically secure random source (`/dev/urandom`,
#' or the \pkg{openssl} package where there is none, as on Windows); without
#' one the service is not started (`CAPABILITY_UNAVAILABLE`).
#' @param read_only Logical; refuse annotation mutations.
#' @param max_body_bytes Maximum request body size.
#' @param serve Logical; start the HTTP listener. With `FALSE` only in-process
#'   calls through the handle are possible (useful in tests).
#' @param call The calling environment, for error reporting.
#'
#' @return An `at_control_handle` (a list with `kind = "local"`, `instance_id`,
#'   `session_id`, `host`, `port`, `pid`, `manifest`, `expires_at`); its print
#'   method never shows the token.
#' @family control
#' @seealso [at_control_stop()], [at_control_command()], [at_app()]
#' @export
#' @examplesIf requireNamespace("httpuv", quietly = TRUE)
#' h <- at_control_start(at_example_session(2), serve = FALSE)
#' at_control_state(h)$state_revision
#' at_control_stop(h)
at_control_start <- function(session, control = "loopback", host = "127.0.0.1", port = 0L,
                             ttl_seconds = 900L, root = NULL, token_file = NULL,
                             read_only = FALSE, max_body_bytes = 1048576L, serve = TRUE,
                             call = rlang::caller_env()) {
  if (!identical(control, "loopback")) {
    .at_abort("{.arg control} must be {.val loopback}; the control service is off unless requested.",
              call = call)
  }
  if (!identical(host, "127.0.0.1")) {
    .at_abort("The control service binds only to {.val 127.0.0.1}.", class = "auth",
              code = "HOST_REJECTED", call = call)
  }
  port <- .check_count(port, call = call)
  ttl_seconds <- .check_count(ttl_seconds, min = 1L, call = call)
  if (ttl_seconds > .interop_limits()$control_max_ttl_seconds) {
    .at_abort("{.arg ttl_seconds} must be at most {(.interop_limits()$control_max_ttl_seconds)}.",
              call = call)
  }
  max_body_bytes <- .check_count(max_body_bytes, min = 1024L, call = call)
  .check_flag(read_only, call = call)
  .check_flag(serve, call = call)
  if (serve) {
    rt <- .control_runtime_status()
    if (!rt$available) {
      .at_abort("The control service needs {.pkg httpuv} and {.pkg later}: {rt$reason}.",
                class = "capability", code = "CAPABILITY_UNAVAILABLE", call = call)
    }
  }
  if (!is.null(token_file)) {
    .check_string(token_file, call = call)
  }
  # The bearer token comes first: without a secure random source (no
  # /dev/urandom and no openssl) this aborts with CAPABILITY_UNAVAILABLE
  # before any directory, token file, registry entry or listener exists.
  token <- .random_hex(32L)
  sess <- .to_session(session, character(), NULL, NULL, call = call)
  root <- root %||% file.path(sess$out_dir, "control")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (serve && port == 0L) {
    port <- httpuv::randomPort(min = 20000L, max = 60000L, host = host)
  }
  hub <- .new_control_hub(sess, root, ttl_seconds, host, port, read_only, max_body_bytes)
  hub$manifest_path <- file.path(root, paste0("annotatr-control-", hub$instance_id, ".json"))
  # The token file is written before the hub is registered, so a refused or
  # failed token file leaves nothing running.
  if (!is.null(token_file)) {
    .control_write_token(token, token_file, call = call)
  }
  assign(hub$instance_id, token, envir = .control_tokens)
  assign(hub$instance_id, hub, envir = .control_registry)
  if (serve) {
    hub$server <- tryCatch(
      httpuv::startServer(host, port, .control_httpuv_app(hub)),
      error = function(e) {
        .control_shutdown(hub, "listen failed")
        if (!is.null(token_file)) unlink(token_file)
        .at_abort("Could not listen on {host}:{port}: {conditionMessage(e)}", class = "io",
                  code = "LISTEN_FAILED", call = call)
      }
    )
    # The timer shuts down anything not already stopped, including a hub a
    # request has just marked expired or one that is closing.
    hub$cancel_expiry <- later::later(function() {
      if (identical(hub$status, "closing")) {
        .control_shutdown(hub, "close requested")
      } else if (!identical(hub$status, "stopped")) {
        .control_shutdown(hub, "ttl expired")
      }
    }, delay = ttl_seconds)
  }
  .hub_event(hub, "service.started", list(read_only = hub$read_only))
  .control_write_manifest(hub, "running")
  .new_control_handle(hub)
}

.new_control_handle <- function(hub) {
  structure(
    list(kind = "local", instance_id = hub$instance_id, session_id = hub$session_id,
         host = hub$host, port = hub$port, pid = hub$pid, manifest = hub$manifest_path,
         expires_at = .utc_stamp(hub$expires_at), serving = !is.null(hub$server)),
    class = "at_control_handle"
  )
}

# The hub behind a local handle, only in the process that started it.
.control_hub <- function(handle, call = rlang::caller_env()) {
  .check_class(handle, "at_control_handle", call = call)
  if (!identical(handle$kind, "local")) {
    .at_abort("This handle refers to a service in another process.", class = "auth",
              code = "NOT_OWNER", call = call)
  }
  if (!identical(as.integer(handle$pid), Sys.getpid())) {
    .at_abort("This control handle belongs to process {handle$pid}, not this one.",
              class = "auth", code = "NOT_OWNER", call = call)
  }
  hub <- .control_registry[[handle$instance_id]]
  if (is.null(hub)) {
    .at_abort("The control service {.val {handle$instance_id}} is not running.",
              class = "protocol", code = "SERVICE_CLOSED", call = call)
  }
  hub
}

#' Stop a local control service
#'
#' Stop a service started by [at_control_start()] in this R process: close the
#' listener, invalidate its token and rewrite its lifecycle manifest as
#' stopped. A handle from another process (or a remote handle from
#' [at_control_connect()]) is refused with an `at_auth_error` (`NOT_OWNER`); no
#' process is ever terminated.
#'
#' @param handle An `at_control_handle` of kind `"local"`.
#' @param call The calling environment, for error reporting.
#' @return `TRUE` invisibly when the service was stopped, `FALSE` if it had
#'   already stopped.
#' @family control
#' @export
at_control_stop <- function(handle, call = rlang::caller_env()) {
  .check_class(handle, "at_control_handle", call = call)
  if (!identical(handle$kind, "local") || !identical(as.integer(handle$pid), Sys.getpid())) {
    .at_abort("Only the process that started a control service can stop it.", class = "auth",
              code = "NOT_OWNER", call = call)
  }
  hub <- .control_registry[[handle$instance_id]]
  if (is.null(hub)) {
    return(invisible(FALSE))
  }
  .control_shutdown(hub, "stopped by owner")
}

#' Close a control service connection
#'
#' Close the control service a handle refers to. For a local handle this is
#' [at_control_stop()]; for a remote handle it sends `POST /v1/close`, after
#' which that service stops accepting requests while its host process and any
#' app keep running. Neither path terminates a process. A close is not
#' revision-checked, so concurrent edits in an attached app never make it
#' fail; unsaved app edits stay in the app.
#'
#' @param handle An `at_control_handle`.
#' @param call The calling environment, for error reporting.
#' @return The close response (remote) or `TRUE` (local), invisibly.
#' @family control
#' @export
at_control_close <- function(handle, call = rlang::caller_env()) {
  .check_class(handle, "at_control_handle", call = call)
  if (identical(handle$kind, "local")) {
    return(at_control_stop(handle, call = call))
  }
  st <- at_control_state(handle, call = call)
  invisible(at_control_command(handle, list(operation = "close", payload = .json_object(),
                                            expected_revision = st$state_revision), call = call))
}

#' @export
print.at_control_handle <- function(x, ...) {
  status <- if (identical(x$kind, "local")) {
    hub <- .control_registry[[x$instance_id]]
    if (is.null(hub)) "stopped" else hub$status
  } else {
    "remote"
  }
  cat(cli::format_inline("{.cls at_control_handle} {x$kind} {x$instance_id} ({status})"), "\n",
      sep = "")
  cat("  http://", x$host, ":", x$port, "  |  token: <redacted>  |  expires ", x$expires_at, "\n",
      sep = "")
  invisible(x)
}
