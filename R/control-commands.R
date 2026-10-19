# Request dispatcher and typed command handlers of `annotatr-control-v1`. The
# same dispatcher serves the loopback HTTP server and in-process handles, so the
# security, validation, revision and idempotency rules are identical on both
# paths. Handlers only call public hyperannotatR functions on the hub's session.

# A classified control failure carried to the response builder.
.control_fail <- function(code, message, details = list(), class = "validation") {
  .at_abort(message, class = class, code = code, details = details)
}

.control_response <- function(hub, status, request_id, data = NULL, error = NULL,
                              warnings = list(), extra = list()) {
  body <- c(list(
    protocol = .contract$control,
    protocol_version = .contract$version,
    request_id = request_id,
    instance_id = hub$instance_id,
    state_revision = as.character(hub$revision),
    event_cursor = .hub_event_cursor(hub)
  ), extra)
  if (!is.null(error)) {
    body$error <- error
  } else {
    body$data <- data %||% .json_object()
  }
  body$warnings <- warnings
  list(status = as.integer(status), body = body)
}

# The error object of a response. Messages and string details are redacted so
# no absolute local path reaches a client (paths below the root become
# root-relative, other absolute paths keep only their last component); the
# full message is kept in the hub's private error log. `class` carries the
# hyperannotatR condition class so a client raises the same class as a local call.
.control_error_body <- function(cnd, hub = NULL) {
  code <- .condition_code(cnd)
  raw_msg <- cli::ansi_strip(conditionMessage(cnd))
  details <- cnd$details %||% list()
  if (!is.null(hub)) {
    hub$error_log <- utils::tail(c(hub$error_log, list(list(time = .utc_stamp(), code = code,
                                                            message = raw_msg))), 50L)
  }
  list(code = code, message_key = tolower(code), message = .control_redact(raw_msg, hub),
       details = if (length(details)) .control_redact(.json_safe(details), hub) else .json_object(),
       retryable = .control_retryable(code), class = .control_condition_class(cnd))
}

# The hyperannotatR class family of a condition ("validation", "conflict", ...);
# errors that are not hyperannotatR conditions are reported as "io".
.control_condition_class <- function(cnd) {
  cls <- grep("^at_[a-z]+_error$", class(cnd), value = TRUE)
  cls <- setdiff(cls, "at_error")
  if (length(cls)) sub("^at_([a-z]+)_error$", "\\1", cls[1]) else "io"
}

# Remove local absolute paths from a message (or recursively from the strings
# of a list).
.control_redact <- function(x, hub = NULL) {
  if (is.list(x)) {
    return(lapply(x, .control_redact, hub = hub))
  }
  if (!is.character(x) || length(x) == 0L) {
    return(x)
  }
  norm <- function(p) {
    p <- p[!is.na(p) & nzchar(p)]
    unique(c(p, normalizePath(p, winslash = "/", mustWork = FALSE)))
  }
  root <- if (is.null(hub)) character() else norm(hub$root)
  prefixes <- list()
  for (r in root) prefixes[[r]] <- ""
  if (!is.null(hub) && .is_string(hub$session$out_dir)) {
    for (r in norm(hub$session$out_dir)) prefixes[[r]] <- "<session>/"
  }
  for (r in norm(tempdir())) prefixes[[r]] <- "<tmp>/"
  home <- norm(path.expand("~"))
  home <- home[nchar(home) > 1L]
  for (r in home) prefixes[[r]] <- "~/"
  keys <- names(prefixes)
  keys <- keys[order(nchar(keys), decreasing = TRUE)]
  for (k in keys) {
    x <- gsub(paste0(.regex_escape(k), "/"), prefixes[[k]], x, perl = TRUE)
    x <- gsub(paste0(.regex_escape(k), "(?![A-Za-z0-9._-])"),
              if (nzchar(prefixes[[k]])) sub("/$", "", prefixes[[k]]) else ".", x, perl = TRUE)
  }
  # Any remaining absolute path: keep only its last component.
  x <- gsub("(^|[\\s'\"`(\\[{=:,])(?:[A-Za-z]:)?(?:[/\\\\][^/\\\\\\s'\"`]+)+[/\\\\]([^/\\\\\\s'\"`]+)",
            "\\1\\2", x, perl = TRUE)
  x
}

.header <- function(headers, name) {
  v <- headers[[tolower(name)]]
  if (is.null(v) || length(v) == 0L || !nzchar(v[1])) NULL else as.character(v[1])
}

.constant_time_equal <- function(a, b) {
  identical(.sha256_bytes(paste0("hyperannotatR-token:", a)), .sha256_bytes(paste0("hyperannotatR-token:", b)))
}

# Security gate shared by every request: Host, Origin, bearer token, TTL.
.control_gate <- function(hub, headers, transport = "http") {
  host <- .header(headers, "host")
  allowed <- c(paste0("127.0.0.1:", hub$port), paste0("localhost:", hub$port))
  if (!identical(transport, "in_process") && (is.null(host) || !host %in% allowed)) {
    .control_fail("HOST_REJECTED", "The Host header is not the loopback control address.",
                  class = "auth")
  }
  if (!is.null(.header(headers, "origin"))) {
    .control_fail("ORIGIN_REJECTED", "Browser-origin requests are not accepted.", class = "auth")
  }
  auth <- .header(headers, "authorization")
  if (is.null(auth) || !grepl("^Bearer [0-9a-f]{64}$", auth)) {
    .control_fail("AUTH_REQUIRED", "A bearer token is required.", class = "auth")
  }
  token <- .control_tokens[[hub$instance_id]]
  if (is.null(token) || !.constant_time_equal(sub("^Bearer ", "", auth), token)) {
    .control_fail("TOKEN_INVALID", "The bearer token is not valid for this instance.", class = "auth")
  }
  if (.control_now() > hub$expires_at) {
    .control_expire(hub)
    .control_fail("TOKEN_EXPIRED", "The control session has expired.", class = "auth")
  }
  if (!identical(hub$status, "running")) {
    .control_fail("SERVICE_CLOSED", "The control service is closed.", class = "protocol")
  }
  invisible(TRUE)
}

# A request found the TTL passed: mark the hub expired and shut it down. With a
# listener the shutdown is deferred to the event loop (the listener is not
# stopped from inside its own request callback); without one it happens now.
# Either way the port, token and registry entry are released and the manifest
# records `expired`, even if the expiry timer never runs (e.g. after sleep).
.control_expire <- function(hub) {
  if (identical(hub$status, "stopped")) {
    return(invisible(FALSE))
  }
  hub$status <- "expired"
  if (!is.null(hub$server) && requireNamespace("later", quietly = TRUE)) {
    if (!isTRUE(hub$expiry_scheduled)) {
      hub$expiry_scheduled <- TRUE
      later::later(function() .control_shutdown(hub, "ttl expired"), delay = 0)
    }
  } else {
    .control_shutdown(hub, "ttl expired")
  }
  invisible(TRUE)
}

# HTTP status for an error code, including the codes this file adds.
.control_status_for <- function(code) {
  switch(
    code,
    UNSAVED_CHANGES = , IDEMPOTENCY_EXPIRED = , IDENTITY_MISMATCH = 409L,
    MASK_TOO_LARGE = 413L,
    .control_http_status(code)
  )
}

# Is a Content-Type header exactly application/json (any case), with an
# optional UTF-8 charset parameter?
.control_media_ok <- function(ctype) {
  if (!.is_string(ctype)) {
    return(FALSE)
  }
  parts <- strsplit(ctype, ";", fixed = TRUE)[[1]]
  if (length(parts) == 0L || !identical(tolower(trimws(parts[1])), "application/json")) {
    return(FALSE)
  }
  for (p in trimws(parts[-1])) {
    if (!nzchar(p)) next
    kv <- strsplit(p, "=", fixed = TRUE)[[1]]
    key <- tolower(trimws(kv[1]))
    val <- tolower(gsub("^\"|\"$", "", trimws(paste(kv[-1], collapse = "="))))
    if (identical(key, "charset") && !val %in% c("utf-8", "utf8")) {
      return(FALSE)
    }
  }
  TRUE
}

.parse_query <- function(query) {
  query <- sub("^\\?", "", query %||% "")
  if (!nzchar(query)) {
    return(list())
  }
  parts <- strsplit(strsplit(query, "&", fixed = TRUE)[[1]], "=", fixed = TRUE)
  out <- lapply(parts, function(p) utils::URLdecode(if (length(p) > 1L) p[2] else ""))
  names(out) <- vapply(parts, function(p) utils::URLdecode(p[1]), character(1))
  out
}

# Dispatch one request (HTTP or in-process) and return list(status, body).
.control_handle_request <- function(hub, method, path, query = "", headers = list(), body = raw(),
                                    transport = "http") {
  names(headers) <- tolower(names(headers))
  request_id <- .header(headers, "x-request-id") %||% paste0("request-", .uuid())
  result <- tryCatch({
    .control_gate(hub, headers, transport)
    if (identical(method, "GET")) {
      .control_get(hub, path, .parse_query(query), request_id)
    } else if (identical(method, "POST")) {
      .control_post(hub, path, headers, body, request_id)
    } else {
      .control_fail("METHOD_NOT_ALLOWED", "Only GET and POST are supported.")
    }
  }, error = function(cnd) {
    code <- .condition_code(cnd)
    .control_response(hub, .control_status_for(code), request_id, error = .control_error_body(cnd, hub))
  })
  result
}

.control_get <- function(hub, path, query, request_id) {
  ok <- function(data) .control_response(hub, 200L, request_id, data = data)
  if (identical(path, "/v1/health")) return(ok(.hub_health(hub)))
  if (identical(path, "/v1/handshake")) return(ok(.hub_handshake(hub)))
  if (identical(path, "/v1/capabilities")) return(ok(at_control_capabilities()))
  if (identical(path, "/v1/state")) return(ok(.hub_state(hub)))
  if (identical(path, "/v1/events")) {
    limit <- query$limit %||% "100"
    if (!grepl("^[0-9]{1,6}$", limit) || as.integer(limit) < 1L) {
      .control_fail("VALIDATION_FAILED", "'limit' must be a positive integer.")
    }
    after <- query$after
    if (!is.null(after) && (nchar(after) > 256L || grepl("[[:cntrl:]]", after))) {
      .control_fail("VALIDATION_FAILED", "'after' is not an event cursor.")
    }
    return(ok(.hub_events_after(hub, after, as.integer(limit))))
  }
  if (grepl("^/v1/requests/[A-Za-z0-9._:-]{1,128}$", path)) {
    id <- sub("^/v1/requests/", "", path)
    rec <- hub$requests[[id]]
    if (is.null(rec)) {
      .control_fail("REQUEST_NOT_FOUND", "No request with this id is known to this instance.")
    }
    return(ok(rec))
  }
  if (!is.null(.control_operation_for(path))) {
    .control_fail("METHOD_NOT_ALLOWED", "This endpoint only accepts POST.")
  }
  .control_fail("ENDPOINT_NOT_FOUND", "Unknown endpoint.")
}

.control_post <- function(hub, path, headers, body, request_id) {
  operation <- .control_operation_for(path)
  if (is.null(operation)) {
    if (grepl("^/v1/(health|handshake|capabilities|state|events|requests)", path)) {
      .control_fail("METHOD_NOT_ALLOWED", "This endpoint only accepts GET.")
    }
    .control_fail("ENDPOINT_NOT_FOUND", "Unknown endpoint.")
  }
  if (!.control_media_ok(.header(headers, "content-type") %||% "")) {
    .control_fail("UNSUPPORTED_MEDIA_TYPE", "Requests must be application/json (UTF-8).")
  }
  if (length(body) > hub$max_body_bytes) {
    .control_fail("PAYLOAD_TOO_LARGE", "The request body exceeds the size limit.",
                  details = list(limit_bytes = hub$max_body_bytes), class = "limit")
  }
  if (any(body == as.raw(0L))) {
    .control_fail("INVALID_JSON", "The request body contains a NUL byte.")
  }
  txt <- rawToChar(body)
  Encoding(txt) <- "UTF-8"
  if (!validUTF8(txt)) {
    .control_fail("INVALID_JSON", "The request body is not valid UTF-8.")
  }
  env <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(env) || is.null(names(env))) {
    .control_fail("INVALID_JSON", "The request body is not a JSON object.")
  }
  if (!identical(env$protocol, .contract$control)) {
    .control_fail("PROTOCOL_MISMATCH", "Unknown protocol.", class = "protocol")
  }
  .check_major_version(env$protocol_version, 1L, "control protocol")
  .schema_assert(env, .contract$control, "command", what = "command")
  if (!identical(env$operation, operation)) {
    .control_fail("VALIDATION_FAILED", "The operation does not match the endpoint.",
                  details = list(endpoint_operation = operation))
  }
  request_id <- env$request_id
  payload <- env$payload %||% .json_object()
  digest <- .digest_json(payload)
  if (!identical(env$content_sha256, digest)) {
    .control_fail("CONTENT_DIGEST_MISMATCH", "content_sha256 does not match the canonical payload.")
  }
  prior_req <- hub$requests[[request_id]]
  prior_key <- hub$idempotency[[env$idempotency_key]]
  if (!is.null(prior_key)) {
    if (!identical(prior_key$content_sha256, digest) || !identical(prior_key$operation, operation)) {
      .control_fail("IDEMPOTENCY_CONFLICT", "This idempotency key was used for a different request.",
                    class = "conflict")
    }
    rec <- hub$requests[[prior_key$request_id]]
    if (is.null(rec)) {
      .control_fail("IDEMPOTENCY_EXPIRED", "The record of this idempotency key is no longer retained; re-read the state.",
                    class = "conflict")
    }
    resp <- rec$response
    resp$body$replayed <- TRUE
    return(resp)
  }
  if (exists(env$idempotency_key, envir = hub$idempotency_evicted, inherits = FALSE)) {
    .control_fail("IDEMPOTENCY_EXPIRED", "The record of this idempotency key is no longer retained; re-read the state.",
                  class = "conflict")
  }
  if (!is.null(prior_req) && !identical(prior_req$content_sha256, digest)) {
    .control_fail("IDEMPOTENCY_CONFLICT", "This request id was used for a different request.",
                  class = "conflict")
  }
  # `close` is not revision-checked: it changes no annotation state, and a
  # concurrent edit in an attached app must not make a close fail.
  mutating <- operation %in% c("session.load", "context.goto", "context.view",
                               "context.selection", "annotations.stage", "annotations.commit",
                               "session.save")
  if (mutating && !identical(as.character(env$expected_revision), as.character(hub$revision))) {
    .control_fail("REVISION_CONFLICT", "The state revision changed; re-read the state.",
                  details = list(expected = env$expected_revision,
                                 actual = as.character(hub$revision)),
                  class = "conflict")
  }
  record <- list(request_id = request_id, operation = operation,
                 idempotency_key = env$idempotency_key, content_sha256 = digest,
                 received_at = .utc_stamp(), extensions = env$extensions %||% .json_object())
  resp <- tryCatch({
    data <- .control_execute(hub, operation, payload, env)
    .control_response(hub, 200L, request_id, data = data)
  }, error = function(cnd) {
    code <- .condition_code(cnd)
    .control_response(hub, .control_status_for(code), request_id, error = .control_error_body(cnd, hub))
  })
  record$status <- if (is.null(resp$body$error)) "completed" else "failed"
  record$http_status <- resp$status
  record$completed_at <- .utc_stamp()
  record$response <- .control_compact_response(resp)
  .hub_record_request(hub, record)
  if (is.null(resp$body$error)) {
    assign(env$idempotency_key, list(content_sha256 = digest, operation = operation,
                                     request_id = request_id), envir = hub$idempotency)
  }
  resp
}

.require_writable <- function(hub) {
  if (isTRUE(hub$read_only)) {
    .control_fail("SCOPE_DENIED", "This control session is read-only.", class = "auth")
  }
}

.payload_int <- function(x, name, min = 0L) {
  if (is.null(x) || !is.numeric(x) || length(x) != 1L || is.na(x) || x != round(x) || x < min) {
    .control_fail("VALIDATION_FAILED", sprintf("'%s' must be an integer >= %d.", name, min))
  }
  as.integer(x)
}

.control_execute <- function(hub, operation, payload, env) {
  origin <- list(kind = "control", request_id = env$request_id)
  tryCatch(.control_dispatch(hub, operation, payload, env, origin),
           error = function(cnd) .control_reclassify(cnd))
}

# Persistence refuses to save or load a project stored in another queue
# entry's slot with a plain error; report it as a conflict a client can act
# on (re-read the state or reload the session) instead of INTERNAL_ERROR.
# Every other condition is re-raised unchanged.
.control_reclassify <- function(cnd) {
  if (!inherits(cnd, "at_error") &&
      grepl("identity does not match", conditionMessage(cnd), fixed = TRUE)) {
    .control_fail("IDENTITY_MISMATCH",
                  "A project is stored under another queue entry; re-read the state or reload the session.",
                  class = "conflict")
  }
  # Re-raise the original condition, keeping its class.
  rlang::cnd_signal(cnd)
}

.control_dispatch <- function(hub, operation, payload, env, origin) {
  switch(
    operation,
    "session.load" = .cmd_session_load(hub, payload, origin),
    "session.save" = .cmd_session_save(hub, payload, origin),
    "context.goto" = .cmd_goto(hub, payload, origin),
    "context.view" = .cmd_view(hub, payload, origin),
    "context.selection" = .cmd_selection(hub, payload, origin),
    "annotations.stage" = .cmd_stage(hub, payload, origin),
    "annotations.commit" = .cmd_commit(hub, payload, env, origin),
    "mask.preview" = .cmd_mask_preview(hub, payload),
    "export" = .cmd_export(hub, payload, origin),
    "training.export" = .cmd_training_export(hub, payload, origin),
    "close" = .cmd_close(hub, origin),
    .control_fail("ENDPOINT_NOT_FOUND", "Unknown operation.")
  )
}

# ---- Handlers -------------------------------------------------------------------

.cmd_session_load <- function(hub, payload, origin) {
  .require_writable(hub)
  if (hub$annotation_status %in% c("unsaved", "staged") && !isTRUE(payload$discard_unsaved)) {
    .control_fail("UNSAVED_CHANGES",
                  "The current session has unsaved or staged changes; save or commit them, or set 'discard_unsaved' to true.",
                  details = list(annotation_status = hub$annotation_status), class = "conflict")
  }
  imgs <- payload$images
  if (!is.list(imgs) || length(imgs) == 0L) {
    .control_fail("VALIDATION_FAILED", "'images' must list image paths relative to the root.")
  }
  paths <- vapply(imgs, function(p) .resolve_under_root(hub$root, as.character(p)), character(1))
  labels <- as.character(unlist(payload$labels %||% list()))
  # A loaded session saves into its own directory under the root, so it never
  # overwrites the checkpoint of the session it replaces.
  session_dir <- paste0("sessions/session-", format(Sys.time(), "%Y%m%dT%H%M%S"), "-", .random_hex(4L))
  out_dir <- file.path(hub$root, session_dir)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  sess <- at_session(paths, labels = labels, out_dir = out_dir)
  if (!is.null(payload$handoff)) {
    dir <- .resolve_under_root(hub$root, as.character(payload$handoff))
    rep <- at_import_qupflowr(dir)
    layers <- rep$objects$layers
    if (length(layers) && all(vapply(layers, inherits, logical(1), "annot_layer"))) {
      p <- .materialize_project(sess, 1L)
      for (L in layers) {
        if (is.null(p$layers[[L$name]])) p <- at_add_layer(p, at_layer(L$name, labels = L$labels, style = L$style))
        for (r in L$rois) p <- at_add_roi(p, L$name, r)
      }
      sess$projects[[1]] <- p
    }
  }
  hub$session <- sess
  hub$generation <- hub$generation + 1L
  hub$view$bounds <- NULL
  hub$view$band_group <- NULL
  hub$selection <- character()
  hub$staged <- NULL
  hub$annotation_status <- "clean"
  .hub_bump(hub, "session.loaded", list(n_images = length(paths), generation = hub$generation), origin)
  list(n_images = length(paths), queue_index = 1L, session_dir = session_dir,
       annotation_revision = at_annotation_revision(sess))
}

.cmd_session_save <- function(hub, payload, origin) {
  .require_writable(hub)
  sess <- hub$session
  sess$projects <- lapply(sess$projects, .lite_project)
  at_save_session(sess, overwrite = TRUE)
  hub$annotation_status <- if (identical(hub$annotation_status, "committed")) "committed" else "clean"
  .hub_bump(hub, "session.saved", list(annotation_revision = at_annotation_revision(hub$session)),
            origin)
  list(saved = TRUE, annotation_revision = at_annotation_revision(hub$session))
}

.cmd_goto <- function(hub, payload, origin) {
  n <- nrow(hub$session$manifest)
  target <- NULL
  if (!is.null(payload$queue_index)) {
    target <- .payload_int(payload$queue_index, "queue_index", 1L)
  } else if (!is.null(payload$entry_id)) {
    # The session's stable entry id (as in handoff manifests); the positional
    # "entry-NNNN" is accepted as an alias.
    want <- as.character(unlist(payload$entry_id))[1]
    ids <- vapply(seq_len(n), function(i) .session_entry_id(hub$session, i), character(1))
    target <- match(want, ids)
    if (is.na(target) && grepl("^entry-[0-9]{4,}$", want %||% "")) {
      target <- suppressWarnings(as.integer(sub("^entry-", "", want)))
    }
  } else if (!is.null(payload$image_id)) {
    # Cached ids first; then hash entries one at a time until one matches.
    want <- as.character(payload$image_id)[1]
    ids <- vapply(seq_len(n), function(i) .hub_image_id(hub, i, lazy = TRUE), character(1))
    target <- match(want, ids)
    if (is.na(target)) {
      for (i in which(is.na(ids))) {
        if (identical(.hub_image_id(hub, i), want)) {
          target <- i
          break
        }
      }
    }
  }
  if (is.null(target) || is.na(target) || target < 1L || target > n) {
    .control_fail("IMAGE_NOT_FOUND", "No queue entry matches the request.")
  }
  # Build the new state completely before the hub changes, so a project that
  # cannot be materialised (unreadable, or IDENTITY_MISMATCH) leaves the hub
  # on its current entry.
  sess <- at_goto(hub$session, target)
  proj <- sess$projects[[target]]
  if (is.null(proj)) {
    proj <- .materialize_project(sess, target)
    sess$projects[[target]] <- proj
  }
  hub$session <- sess
  hub$selection <- character()
  hub$staged <- NULL
  hub$view$bounds <- NULL
  eid <- .session_entry_id(hub$session, target)
  .hub_bump(hub, "image.changed", list(queue_index = target, entry_id = eid), origin)
  list(queue_index = target, entry_id = eid,
       image_id = .hub_image_id(hub, target), annotation_revision = at_annotation_revision(proj))
}

.cmd_view <- function(hub, payload, origin) {
  proj <- .hub_project(hub)
  img <- proj$image
  view <- hub$view
  if (!is.null(payload$level)) {
    lvl <- .payload_int(payload$level, "level", 0L)
    if (lvl > img$n_levels - 1L) {
      .control_fail("VALIDATION_FAILED", "The level does not exist for this image.")
    }
    view$level <- lvl
  }
  if (!is.null(payload$bounds)) {
    b <- suppressWarnings(as.numeric(unlist(payload$bounds)))
    d <- img$level_dims[[1]]
    if (length(b) != 4L || anyNA(b) || b[1] >= b[3] || b[2] >= b[4] ||
        b[1] < 0 || b[2] < 0 || b[3] > d[1] || b[4] > d[2]) {
      .control_fail("VALIDATION_FAILED", "bounds must be [xmin, ymin, xmax, ymax] inside the image (level-0 px).")
    }
    view$bounds <- as.list(b)
  }
  if (!is.null(payload$band_group)) {
    bg <- payload$band_group
    spec <- tryCatch(
      .check_band_view(img, bg$operation %||% "rgb",
                       if (is.null(bg$bands)) NULL else as.integer(unlist(bg$bands)),
                       bg$params %||% list()),
      error = function(e) {
        .control_fail(.condition_code(e) %||% "VALIDATION_FAILED", cli::ansi_strip(conditionMessage(e)))
      }
    )
    view$band_group <- list(operation = spec$operation, bands = as.list(spec$bands),
                            params = if (length(spec$params)) spec$params else .json_object())
  }
  if (!is.null(payload$tool)) {
    tool <- as.character(payload$tool)
    if (!tool %in% .canvas_tool_names) {
      .control_fail("VALIDATION_FAILED", "Unknown tool.")
    }
    if (hub$read_only && !tool %in% c("pan", "probe", "select")) {
      .control_fail("SCOPE_DENIED", "Drawing tools are disabled in a read-only session.", class = "auth")
    }
    view$tool <- tool
  }
  if (!is.null(payload$overlay)) {
    ov <- payload$overlay
    mt <- ov$mask_type %||% "labelled"
    if (!mt %in% c("binary", "labelled", "multiclass")) {
      .control_fail("VALIDATION_FAILED", "Unknown overlay mask_type.")
    }
    alpha <- as.numeric(ov$alpha %||% 0.5)
    if (length(alpha) != 1L || is.na(alpha) || alpha < 0 || alpha > 1) {
      .control_fail("VALIDATION_FAILED", "overlay alpha must be in [0, 1].")
    }
    view$overlay <- list(show = isTRUE(ov$show), mask_type = mt, alpha = alpha)
  }
  hub$view <- view
  .hub_bump(hub, "view.changed", list(view = view), origin)
  list(view = view)
}

.cmd_selection <- function(hub, payload, origin) {
  ids <- as.character(unlist(payload$roi_ids %||% list()))
  proj <- .hub_project(hub)
  known <- .all_roi_ids(proj)
  missing <- setdiff(ids, known)
  if (length(missing)) {
    .control_fail("VALIDATION_FAILED", "Unknown ROI ids in the selection.",
                  details = list(missing = as.list(utils::head(missing, 20L))))
  }
  hub$selection <- ids
  .hub_bump(hub, "selection.changed", list(roi_ids = as.list(ids)), origin)
  list(roi_ids = as.list(ids))
}

.cmd_stage <- function(hub, payload, origin) {
  .require_writable(hub)
  proj <- .hub_project(hub)
  report <- if (!is.null(payload$payload_ref)) {
    ref <- .resolve_under_root(hub$root, as.character(payload$payload_ref))
    if (!is.null(payload$payload_sha256) && !dir.exists(ref) &&
        !identical(.sha256_file(ref), payload$payload_sha256)) {
      .control_fail("CONTENT_DIGEST_MISMATCH", "payload_ref does not match payload_sha256.")
    }
    at_import_qupflowr(ref)
  } else if (!is.null(payload$features)) {
    feats <- payload$features
    if (length(feats) > .interop_limits()$control_max_inline_features) {
      .control_fail("PAYLOAD_TOO_LARGE", "Too many inline features.", class = "limit")
    }
    tmp <- tempfile(fileext = ".geojson")
    on.exit(unlink(tmp), add = TRUE)
    jsonlite::write_json(list(type = "FeatureCollection", features = feats), tmp,
                         auto_unbox = TRUE, digits = I(17), null = "null")
    at_import_qupflowr(tmp, format = "qupath_geojson")
  } else {
    .control_fail("VALIDATION_FAILED", "Provide 'payload_ref' or inline 'features'.")
  }
  patch <- at_stage_qupflowr(proj, report, expected_revision = payload$expected_annotation_revision,
                             delete_missing = isTRUE(payload$delete_missing))
  hub$staged <- patch
  hub$annotation_status <- "staged"
  .hub_bump(hub, "annotations.staged", list(patch_id = patch$patch_id, summary = patch$summary),
            origin)
  ops <- patch$operations
  list(patch_id = patch$patch_id, summary = patch$summary,
       base_revision = patch$base_revision, proposed_revision = patch$proposed_revision,
       operations = lapply(seq_len(min(nrow(ops), 2000L)), function(i) as.list(ops[i, ])),
       operations_truncated = nrow(ops) > 2000L)
}

.cmd_commit <- function(hub, payload, env, origin) {
  .require_writable(hub)
  st <- hub$staged
  if (is.null(st) || !identical(payload$patch_id, st$patch_id)) {
    .control_fail("PATCH_NOT_FOUND", "No staged patch with this id.")
  }
  proj <- .hub_project(hub)
  if (!identical(at_annotation_revision(proj), st$base_revision)) {
    hub$staged <- NULL
    .control_fail("REVISION_CONFLICT", "The image annotations changed since staging; stage again.",
                  class = "conflict")
  }
  rc <- at_commit_qupflowr(st, idempotency_key = paste0("control:", env$idempotency_key))
  i <- hub$session$cursor
  # Save the committed session first; the hub changes only after the save
  # succeeded, so a failed save leaves the hub, its revision and the staged
  # patch as they were and the client can retry.
  sess <- hub$session
  sess$projects[[i]] <- rc$project
  sess$manifest$n_rois[i] <- nrow(at_rois(rc$project))
  saved <- sess
  saved$projects <- lapply(saved$projects, .lite_project)
  at_save_session(saved, overwrite = TRUE)
  hub$session <- sess
  hub$staged <- NULL
  hub$annotation_status <- "committed"
  hub$last_commit <- list(patch_id = rc$patch_id, new_revision = rc$new_revision,
                          previous_revision = rc$previous_revision,
                          committed_at = rc$committed_at, applied = nrow(rc$applied),
                          conflicts = nrow(rc$conflicts))
  .hub_bump(hub, "annotations.committed", hub$last_commit, origin)
  c(hub$last_commit, list(session_saved = TRUE))
}

.cmd_mask_preview <- function(hub, payload) {
  proj <- .hub_project(hub)
  mt <- payload$mask_type %||% "labelled"
  if (!mt %in% c("binary", "labelled", "multiclass")) {
    .control_fail("VALIDATION_FAILED", "Unknown mask_type.")
  }
  overlap <- payload$overlap %||% "last"
  if (!overlap %in% c("last", "first", "max", "min", "bitor")) {
    .control_fail("VALIDATION_FAILED", "Unknown overlap policy.")
  }
  img <- proj$image
  budget <- .control_mask_max_pixels()
  px <- vapply(img$level_dims, function(d) as.numeric(d[1]) * as.numeric(d[2]), numeric(1))
  if (is.null(payload$level)) {
    # The finest level whose full mask fits the pixel budget.
    fits <- which(px <= budget)
    level <- if (length(fits)) min(fits) - 1L else img$n_levels - 1L
  } else {
    level <- .payload_int(payload$level, "level", 0L)
  }
  if (level > img$n_levels - 1L) {
    .control_fail("VALIDATION_FAILED", "The level does not exist for this image.")
  }
  if (px[level + 1L] > budget) {
    .control_fail("MASK_TOO_LARGE",
                  "A mask at this level exceeds the preview pixel budget; request a coarser level.",
                  details = list(level = level, pixels = px[level + 1L], limit_pixels = budget),
                  class = "limit")
  }
  max_dim <- min(.payload_int(payload$max_dim %||% 256L, "max_dim", 1L),
                 .interop_limits()$mask_preview_max_dim)
  m <- at_mask(proj, type = mt, level = level, overlap = overlap)
  pv <- at_mask_preview(m, max_dim = max_dim)
  rec <- .mask_record(m)
  out <- list(mask_type = mt, level = level, width = rec$width, height = rec$height,
              preview_width = ncol(as.matrix(pv)), preview_height = nrow(as.matrix(pv)),
              legend = rec$legend, legend_sha256 = rec$legend_sha256,
              mask_sha256 = .sha256_bytes(writeBin(as.integer(as.matrix(m)), raw(), size = 4L, endian = "little")))
  if (isTRUE(payload$include_png)) {
    out$png_base64 <- sub("^data:image/png;base64,", "", .mask_data_uri(pv, max_dim = max_dim) %||% "")
  }
  .hub_event(hub, "mask.previewed", list(mask_type = mt, level = level))
  out
}

# Pixel budget of a full mask built for mask.preview (the mask is rasterised at
# the chosen level before it is downsampled).
.control_mask_max_pixels <- function() {
  as.numeric(getOption("hyperannotatR.control_mask_max_pixels", 4096^2))
}

# An output directory `<root>/<sub>/<name>`. The resolved parent and an
# existing destination (including a symbolic link) must stay below the root.
.control_output_dir <- function(hub, sub, name) {
  if (!.is_string(name) || !grepl("^[A-Za-z0-9._-]{1,64}$", name) || name %in% c(".", "..")) {
    .control_fail("VALIDATION_FAILED", "'destination' must be a simple name of letters, digits, '.', '_' or '-'.")
  }
  root <- normalizePath(hub$root, winslash = "/", mustWork = TRUE)
  inside <- function(p) identical(p, root) || startsWith(p, paste0(root, "/"))
  outside <- function() {
    .at_abort("The output destination resolves outside the negotiated root.", class = "io",
              code = "PATH_OUTSIDE_ROOT")
  }
  base <- file.path(root, sub)
  if (.is_symlink(base) && !dir.exists(base)) outside()
  dir.create(base, recursive = TRUE, showWarnings = FALSE)
  real_base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  if (!inside(real_base)) outside()
  dest <- file.path(real_base, name)
  if (.is_symlink(dest)) {
    target <- normalizePath(dest, winslash = "/", mustWork = FALSE)
    if (!file.exists(dest) || !inside(target)) outside()
  }
  dest
}

.cmd_export <- function(hub, payload, origin) {
  dest <- .control_output_dir(hub, "exports", payload$destination)
  formats <- as.character(unlist(payload$formats %||% list("qupath_geojson", "mask_tiff", "manifest")))
  scope <- payload$scope %||% "current"
  if (!scope %in% c("current", "all", "complete")) {
    .control_fail("VALIDATION_FAILED", "scope must be current, all or complete.")
  }
  x <- if (identical(scope, "current")) .hub_project(hub) else hub$session
  if (!identical(scope, "current")) {
    hub$session$projects[[hub$session$cursor]] <- .hub_project(hub)
    x <- hub$session
  }
  rc <- at_export_qupflowr(x, dest, formats = formats, overwrite = isTRUE(payload$overwrite),
                           scope = if (identical(scope, "current")) "all" else scope)
  out <- list(destination = paste0("exports/", basename(dest)), handoff_digest = rc$handoff_digest,
              files = lapply(seq_len(nrow(rc$files)), function(i) as.list(rc$files[i, ])),
              skipped = as.list(rc$skipped))
  .hub_event(hub, "export.completed", list(destination = out$destination,
                                           handoff_digest = rc$handoff_digest), origin)
  out
}

.cmd_training_export <- function(hub, payload, origin) {
  dest <- .control_output_dir(hub, "training", payload$destination)
  hub$session$projects[[hub$session$cursor]] <- .hub_project(hub)
  split <- payload$split
  rc <- at_training_export(
    hub$session, dest,
    split = if (is.null(split)) NULL else lapply(split, function(v) if (is.list(v)) unlist(v) else v),
    tile_size = .payload_int(payload$tile_size %||% 256L, "tile_size", 8L),
    overlap = .payload_int(payload$overlap %||% 0L, "overlap", 0L),
    level = .payload_int(payload$level %||% 0L, "level", 0L),
    mask_type = payload$mask_type %||% "labelled",
    bands = if (is.null(payload$bands)) NULL else as.integer(unlist(payload$bands)),
    seed = .payload_int(payload$seed %||% 1L, "seed", 0L),
    overwrite = isTRUE(payload$overwrite)
  )
  out <- list(destination = paste0("training/", basename(dest)), dataset_digest = rc$dataset_digest,
              counts = rc$manifest$counts, checks = lapply(seq_len(nrow(rc$checks)), function(i) as.list(rc$checks[i, ])))
  .hub_event(hub, "training.exported", list(destination = out$destination,
                                            dataset_digest = rc$dataset_digest), origin)
  out
}

.cmd_close <- function(hub, origin) {
  .hub_bump(hub, "connection.closing", list(reason = "close requested"), origin)
  hub$status <- "closing"
  if (!is.null(hub$server) && requireNamespace("later", quietly = TRUE)) {
    later::later(function() .control_shutdown(hub, "close requested"), delay = 0.2)
  } else {
    .control_shutdown(hub, "close requested")
  }
  list(closing = TRUE, instance_id = hub$instance_id)
}
