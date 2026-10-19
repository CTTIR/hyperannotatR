# annotatr-control-v1 through the shared dispatcher (in-process transport).
# The HTTP transport is exercised separately in test-control-http.R.
skip_if_not_installed("magick")

local_control <- function(n = 3L, ..., .env = parent.frame()) {
  h <- at_control_start(at_example_session(n), serve = FALSE, ...)
  withr::defer(suppressWarnings(tryCatch(at_control_stop(h), error = function(e) NULL)), envir = .env)
  h
}

cmd <- function(h, operation, payload = list(), rev = at_control_state(h)$state_revision, ...) {
  at_control_command(h, list(operation = operation, payload = payload, expected_revision = rev, ...))
}

raw_post <- function(h, path, body, token = .control_tokens[[h$instance_id]], headers = list()) {
  hdr <- utils::modifyList(list(authorization = paste("Bearer", token), `content-type` = "application/json"),
                           headers)
  txt <- if (is.character(body)) body else as.character(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"))
  .control_handle_request(.control_hub(h), "POST", path, headers = hdr, body = charToRaw(txt),
                          transport = "in_process")
}

envelope <- function(operation, payload, rev, ...) {
  wire <- jsonlite::fromJSON(jsonlite::toJSON(payload, auto_unbox = TRUE), simplifyVector = FALSE)
  c(list(protocol = "annotatr-control-v1", protocol_version = "1.0",
         request_id = paste0("r-", .random_hex(4)), expected_revision = rev,
         idempotency_key = paste0("k-", .random_hex(4)), operation = operation,
         content_sha256 = .digest_json(if (length(wire)) wire else .json_object()),
         payload = if (length(payload)) payload else .json_object()), list(...))
}

schema_ok <- function(value, name) {
  expect_length(.schema_validate(.as_json_value(value), .schema_load("annotatr-control-v1", name)), 0L)
}

test_that("handshake, health, state and capabilities satisfy their schemas", {
  h <- local_control()
  hub <- .control_hub(h)
  tok <- .control_tokens[[h$instance_id]]
  for (path in c("/v1/handshake", "/v1/health", "/v1/state", "/v1/capabilities")) {
    res <- .control_handle_request(hub, "GET", path, headers = list(authorization = paste("Bearer", tok)),
                                   transport = "in_process")
    expect_identical(res$status, 200L, label = path)
    schema_ok(res$body, "response")
  }
  schema_ok(at_control_state(h), "state")
  hs <- .control_call(h, "GET", "/v1/handshake")
  schema_ok(hs, "handshake")
  expect_identical(hs$instance_id, h$instance_id)
  expect_identical(hs$coordinate_convention$y_axis, "down")
  health <- .control_call(h, "GET", "/v1/health")
  schema_ok(health, "health")
  expect_null(health$queue)
  expect_false(grepl(tok, jsonlite::toJSON(unclass(h), auto_unbox = TRUE, force = TRUE), fixed = TRUE))
  expect_false(grepl(tok, paste(readLines(h$manifest), collapse = ""), fixed = TRUE))
  expect_output(print(h), "<redacted>")
})

test_that("typed commands move the state revision and emit cursor-addressed events", {
  h <- local_control()
  st0 <- at_control_state(h)
  expect_identical(st0$state_revision, "0")
  g <- cmd(h, "context.goto", list(queue_index = 2))
  # Entry ids are the session's stable ids, the same ones handoff manifests use.
  hub <- .control_hub(h)
  expect_identical(g$entry_id, .session_entry_id(hub$session, 2L))
  expect_identical(g$entry_id, st0$queue[[2]]$entry_id)
  expect_identical(g$entry_id, hub$session$manifest$entry_id[2])
  st1 <- at_control_state(h)
  expect_identical(st1$state_revision, "1")
  expect_identical(st1$current$queue_index, 2L)
  expect_identical(st1$current$entry_id, g$entry_id)
  by_id <- cmd(h, "context.goto", list(entry_id = st0$queue[[3]]$entry_id))
  expect_identical(by_id$queue_index, 3L)
  by_position <- cmd(h, "context.goto", list(entry_id = "entry-0002"))
  expect_identical(by_position$queue_index, 2L)
  expect_identical(by_position$entry_id, st0$queue[[2]]$entry_id)
  expect_identical(tryCatch(cmd(h, "context.goto", list(entry_id = "entry_nope")), error = function(e) e$code),
                   "IMAGE_NOT_FOUND")
  v <- cmd(h, "context.view", list(level = 0, bounds = list(0, 0, 100, 80), tool = "select",
                                   band_group = list(operation = "single", bands = list(2)),
                                   overlay = list(show = TRUE, mask_type = "multiclass", alpha = 0.3)))
  expect_identical(v$view$tool, "select")
  ev <- at_control_events(h, after = paste0(h$instance_id, ":1"))
  expect_identical(vapply(ev$events, `[[`, character(1), "type"),
                   c(rep("image.changed", 3L), "view.changed"))
  expect_identical(vapply(ev$events[1:3], function(e) e$payload$entry_id, character(1)),
                   c(st0$queue[[2]]$entry_id, st0$queue[[3]]$entry_id, st0$queue[[2]]$entry_id))
  for (e in ev$events) schema_ok(e, "event")
  schema_ok(ev, "events-page")
  expect_false(ev$resync_required)
  none <- at_control_events(h, after = ev$next_cursor)
  expect_length(none$events, 0L)
  expect_identical(none$next_cursor, ev$next_cursor)
  expect_true(at_control_events(h, after = "instance-other:3")$resync_required)
  expect_identical(tryCatch(cmd(h, "context.view", list(bounds = list(0, 0, 9999, 10))),
                            error = function(e) e$code), "VALIDATION_FAILED")
  expect_identical(tryCatch(cmd(h, "context.view", list(band_group = list(operation = "eval", bands = list(1)))),
                            error = function(e) e$code), "VALIDATION_FAILED")
  expect_identical(tryCatch(cmd(h, "context.goto", list(queue_index = 9)), error = function(e) e$code),
                   "IMAGE_NOT_FOUND")
})

test_that("stale revisions conflict and idempotency keys replay without re-applying", {
  h <- local_control()
  rev <- at_control_state(h)$state_revision
  first <- cmd(h, "context.goto", list(queue_index = 2), rev = rev, idempotency_key = "idem-1",
               request_id = "req-1")
  expect_identical(at_control_state(h)$state_revision, "1")
  err <- tryCatch(cmd(h, "context.goto", list(queue_index = 3), rev = rev), error = function(e) e)
  expect_s3_class(err, "at_conflict_error")
  expect_identical(err$code, "REVISION_CONFLICT")
  expect_true(err$details$retryable)
  # Response loss: the client re-sends the same request with the same key.
  again <- cmd(h, "context.goto", list(queue_index = 2), rev = rev, idempotency_key = "idem-1",
               request_id = "req-1")
  expect_true(attr(again, "response")$replayed)
  expect_identical(at_control_state(h)$state_revision, "1")
  rec <- at_control_request_status(h, "req-1")
  schema_ok(rec, "request-record")
  expect_identical(rec$status, "completed")
  expect_identical(rec$operation, "context.goto")
  err <- tryCatch(cmd(h, "context.goto", list(queue_index = 3), rev = "1", idempotency_key = "idem-1"),
                  error = function(e) e)
  expect_identical(err$code, "IDEMPOTENCY_CONFLICT")
  expect_identical(tryCatch(at_control_request_status(h, "never-sent"), error = function(e) e$code),
                   "REQUEST_NOT_FOUND")
  expect_identical(at_control_state(h)$state_revision, "1")
})

test_that("envelopes are validated: version, fields, digest, operation and media type", {
  h <- local_control()
  good <- envelope("context.goto", list(queue_index = 2), "0")
  bad_major <- good; bad_major$protocol_version <- "2.0"
  expect_identical(raw_post(h, "/v1/context/goto", bad_major)$body$error$code, "PROTOCOL_MISMATCH")
  extra <- good; extra$surprise <- TRUE
  expect_identical(raw_post(h, "/v1/context/goto", extra)$body$error$code, "SCHEMA_INVALID")
  digest <- good; digest$content_sha256 <- strrep("0", 64)
  expect_identical(raw_post(h, "/v1/context/goto", digest)$body$error$code, "CONTENT_DIGEST_MISMATCH")
  expect_identical(raw_post(h, "/v1/context/view", good)$body$error$code, "VALIDATION_FAILED")
  expect_identical(raw_post(h, "/v1/context/goto", "not json")$body$error$code, "INVALID_JSON")
  res <- raw_post(h, "/v1/context/goto", good, headers = list(`content-type` = "text/plain"))
  expect_identical(res$status, 415L)
  with_ext <- envelope("context.goto", list(queue_index = 2), "0",
                       extensions = list(`org.example.trace` = list(span = "abc")))
  ok <- raw_post(h, "/v1/context/goto", with_ext)
  expect_identical(ok$status, 200L)
  rec <- at_control_request_status(h, with_ext$request_id)
  expect_identical(rec$extensions$`org.example.trace`$span, "abc")
  hub <- .control_hub(h)
  tok <- .control_tokens[[h$instance_id]]
  get405 <- .control_handle_request(hub, "GET", "/v1/context/goto",
                                    headers = list(authorization = paste("Bearer", tok)), transport = "in_process")
  expect_identical(get405$status, 405L)
  for (p in c("/v1/eval", "/v1/shell", "/v1/dom/click", "/v1/r")) {
    expect_identical(raw_post(h, p, good)$status, 404L)
  }
  big <- raw_post(h, "/v1/context/goto", paste0('{"x":"', strrep("a", 1100000), '"}'))
  expect_identical(big$body$error$code, "PAYLOAD_TOO_LARGE")
  expect_identical(big$status, 413L)
})

test_that("tokens, origins, hosts and TTL gate every request", {
  a <- local_control(1)
  b <- local_control(1)
  hub_a <- .control_hub(a)
  tok_b <- .control_tokens[[b$instance_id]]
  cross <- .control_handle_request(hub_a, "GET", "/v1/state",
                                   headers = list(authorization = paste("Bearer", tok_b)), transport = "in_process")
  expect_identical(cross$body$error$code, "TOKEN_INVALID")
  tok_a <- .control_tokens[[a$instance_id]]
  expect_identical(.control_handle_request(hub_a, "GET", "/v1/state",
                                           headers = list(authorization = paste("Bearer", tok_a),
                                                          origin = "http://evil.example"),
                                           transport = "in_process")$body$error$code, "ORIGIN_REJECTED")
  expect_identical(.control_handle_request(hub_a, "GET", "/v1/state",
                                           headers = list(authorization = paste("Bearer", tok_a),
                                                          host = "evil.example:80"))$body$error$code,
                   "HOST_REJECTED")
  expect_identical(.control_handle_request(hub_a, "GET", "/v1/state", headers = list(),
                                           transport = "in_process")$status, 401L)
  short <- local_control(1, ttl_seconds = 1L)
  local_mocked_bindings(.control_now = function() Sys.time() + 3600)
  err <- tryCatch(at_control_state(short), error = function(e) e)
  expect_s3_class(err, "at_auth_error")
  expect_identical(err$code, "TOKEN_EXPIRED")
  # (S7) Without a listener the expired service is shut down at once.
  expect_identical(tryCatch(at_control_state(short), error = function(e) e$code), "SERVICE_CLOSED")
  expect_identical(jsonlite::read_json(short$manifest)$state, "expired")
  expect_error(at_control_start(at_example_session(1), host = "0.0.0.0", serve = FALSE),
               class = "at_auth_error")
  expect_error(at_control_start(at_example_session(1), control = "off", serve = FALSE))
})

test_that("an event gap beyond the retained buffer forces a resync", {
  base <- .interop_limits()
  local_mocked_bindings(.interop_limits = function() utils::modifyList(base, list(control_max_events_buffer = 3L)))
  h <- local_control(3)
  first <- at_control_events(h)$next_cursor
  for (i in 1:5) cmd(h, "context.selection", list(roi_ids = list()))
  ev <- at_control_events(h, after = first)
  expect_true(ev$resync_required)
  expect_length(ev$events, 3L)
})

test_that("annotations stage, commit and export through relative references only", {
  h <- local_control(1)
  hub <- .control_hub(h)
  proj <- at_example_project()
  partner <- file.path(hub$root, "incoming", "handoff")
  at_export_qupflowr(proj, partner, formats = "qupath_geojson")
  staged <- cmd(h, "annotations.stage", list(payload_ref = "incoming/handoff"))
  expect_identical(staged$summary$create, 3L)
  expect_identical(at_control_state(h)$annotation_status, "staged")
  expect_identical(tryCatch(cmd(h, "annotations.commit", list(patch_id = "wrong")), error = function(e) e$code),
                   "PATCH_NOT_FOUND")
  done <- cmd(h, "annotations.commit", list(patch_id = staged$patch_id), idempotency_key = "commit-1")
  expect_identical(done$applied, 3L)
  st <- at_control_state(h)
  expect_identical(st$annotation_status, "committed")
  expect_identical(length(st$current$rois), 3L)
  expect_true(file.exists(file.path(hub$session$out_dir, "_session.rds")))
  sel <- cmd(h, "context.selection", list(roi_ids = list(st$current$rois[[1]]$roi_id)))
  expect_length(sel$roi_ids, 1L)
  expect_identical(tryCatch(cmd(h, "context.selection", list(roi_ids = list("ghost"))),
                            error = function(e) e$code), "VALIDATION_FAILED")
  for (ref in c("../outside", "/etc/passwd", "incoming/../../x")) {
    expect_identical(tryCatch(cmd(h, "annotations.stage", list(payload_ref = ref)), error = function(e) e$code),
                     "PATH_OUTSIDE_ROOT", label = ref)
  }
  ex <- cmd(h, "export", list(destination = "handoff-1", formats = list("qupath_geojson", "mask_tiff")))
  expect_identical(ex$destination, "exports/handoff-1")
  expect_true(file.exists(file.path(hub$root, "exports", "handoff-1", "integrity.json")))
  expect_identical(tryCatch(cmd(h, "export", list(destination = "../x")), error = function(e) e$code),
                   "VALIDATION_FAILED")
  mp <- cmd(h, "mask.preview", list(mask_type = "labelled", max_dim = 32, include_png = TRUE))
  expect_identical(mp$preview_width <= 32L, TRUE)
  expect_match(mp$png_base64, "^[A-Za-z0-9+/=]+$")
  expect_identical(mp$mask_sha256, .sha256_bytes(writeBin(as.integer(as.matrix(at_mask(.hub_project(hub), "labelled"))),
                                                          raw(), size = 4L, endian = "little")))
})

test_that("read-only control sessions refuse mutations but allow viewing", {
  h <- local_control(2, read_only = TRUE)
  expect_identical(at_control_state(h)$mode, "read_only")
  cmd(h, "context.goto", list(queue_index = 2))
  expect_identical(tryCatch(cmd(h, "annotations.stage", list(features = list())), error = function(e) e$code),
                   "SCOPE_DENIED")
  expect_identical(tryCatch(cmd(h, "context.view", list(tool = "rect")), error = function(e) e$code),
                   "SCOPE_DENIED")
  expect_identical(tryCatch(cmd(h, "session.save", list()), error = function(e) e$code), "SCOPE_DENIED")
})

test_that("stop is owner-only, close stops only the service, and handles are process-bound", {
  h <- at_control_start(at_example_session(1), serve = FALSE)
  foreign <- h
  foreign$pid <- h$pid + 100000L
  expect_identical(tryCatch(at_control_stop(foreign), error = function(e) e$code), "NOT_OWNER")
  expect_identical(tryCatch(at_control_state(foreign), error = function(e) e$code), "NOT_OWNER")
  remote <- h
  remote$kind <- "remote"
  expect_identical(tryCatch(at_control_stop(remote), error = function(e) e$code), "NOT_OWNER")
  closed <- cmd(h, "close", list())
  expect_true(closed$closing)
  expect_identical(tryCatch(at_control_state(h), error = function(e) e$code), "SERVICE_CLOSED")
  man <- jsonlite::read_json(h$manifest)
  expect_identical(man$state, "stopped")
  expect_identical(man$stop_reason, "close requested")
  expect_false(at_control_stop(h))
})

test_that("the in-process listener answers real HTTP requests on the loopback port", {
  skip_if_not_installed("curl")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
  root <- withr::local_tempdir()
  h <- at_control_start(at_example_session(1), root = root, token_file = file.path(root, "tok"))
  withr::defer(at_control_stop(h))
  expect_true(h$serving)
  tok <- readLines(file.path(root, "tok"))
  fetch <- function(path, headers) {
    result <- NULL
    hd <- curl::new_handle()
    do.call(curl::handle_setheaders, c(list(hd), headers))
    curl::curl_fetch_multi(sprintf("http://127.0.0.1:%d%s", h$port, path),
                           done = function(res) result <<- res, fail = function(msg) result <<- msg,
                           handle = hd)
    deadline <- Sys.time() + 10
    while (is.null(result) && Sys.time() < deadline) {
      curl::multi_run(timeout = 0.05, poll = TRUE)
      later::run_now(0.05)
    }
    result
  }
  ok <- fetch("/v1/health", list(Authorization = paste("Bearer", tok)))
  expect_identical(ok$status_code, 200L)
  body <- jsonlite::fromJSON(rawToChar(ok$content), simplifyVector = FALSE)
  expect_identical(body$data$instance_id, h$instance_id)
  expect_identical(fetch("/v1/state", list())$status_code, 401L)
  expect_identical(tryCatch(at_control_start(at_example_session(1), root = root,
                                             token_file = file.path(root, "tok"), serve = FALSE),
                            error = function(e) e$code), "DESTINATION_EXISTS")
})

test_that("remote connections are validated before any request and errors map to classes", {
  root <- withr::local_tempdir()
  h <- at_control_start(at_example_session(1), root = root, serve = FALSE)
  at_control_stop(h)
  tok <- file.path(root, "tok")
  writeLines(strrep("a", 64), tok)
  expect_identical(tryCatch(at_control_connect(h$manifest, tok), error = function(e) e$code), "SERVICE_CLOSED")
  man <- jsonlite::read_json(h$manifest)
  man$state <- "running"
  man$protocol <- "other"
  jsonlite::write_json(man, h$manifest, auto_unbox = TRUE, null = "null")
  expect_identical(tryCatch(at_control_connect(h$manifest, tok), error = function(e) e$code), "PROTOCOL_MISMATCH")
  man$protocol <- "annotatr-control-v1"
  man$host <- "0.0.0.0"
  jsonlite::write_json(man, h$manifest, auto_unbox = TRUE, null = "null")
  expect_identical(tryCatch(at_control_connect(h$manifest, tok), error = function(e) e$code), "HOST_REJECTED")
  man$host <- "127.0.0.1"
  jsonlite::write_json(man, h$manifest, auto_unbox = TRUE, null = "null")
  writeLines("not-a-token", tok)
  expect_identical(tryCatch(at_control_connect(h$manifest, tok), error = function(e) e$code), "TOKEN_INVALID")
  for (st in list(c("409", "at_conflict_error"), c("401", "at_auth_error"), c("413", "at_limit_error"),
                  c("501", "at_capability_error"), c("422", "at_validation_error"))) {
    err <- tryCatch(.control_raise(list(error = list(code = "X", message = "m"), request_id = "r"),
                                   as.integer(st[1]), rlang::current_env()), error = function(e) e)
    expect_s3_class(err, st[2])
  }
  remote <- structure(list(kind = "remote", instance_id = "instance-x", host = "127.0.0.1", port = 1L,
                           pid = 1L, manifest = "m", expires_at = "t", serving = TRUE),
                      class = "at_control_handle")
  expect_identical(tryCatch(at_control_state(remote), error = function(e) e$code), "AUTH_REQUIRED")
  expect_output(print(remote), "remote")
  expect_error(at_control_command(h, list(operation = "bogus")), class = "at_validation_error")
  expect_error(at_control_command(h, "context.goto"), class = "at_validation_error")
})

test_that("(S10) a commit whose session save fails leaves the hub unchanged and can be retried", {
  h <- local_control(1)
  hub <- .control_hub(h)
  at_export_qupflowr(at_example_project(), file.path(hub$root, "incoming", "handoff"),
                     formats = "qupath_geojson")
  staged <- cmd(h, "annotations.stage", list(payload_ref = "incoming/handoff"))
  rev <- at_control_state(h)$state_revision
  err <- with_mocked_bindings(
    tryCatch(cmd(h, "annotations.commit", list(patch_id = staged$patch_id)), error = function(e) e),
    at_save_session = function(...) stop("disk full")
  )
  expect_s3_class(err, "at_io_error")
  st <- at_control_state(h)
  expect_identical(st$state_revision, rev)
  expect_length(st$current$rois, 0L)
  expect_identical(st$annotation_status, "staged")
  expect_identical(st$staged$patch_id, staged$patch_id)
  done <- cmd(h, "annotations.commit", list(patch_id = staged$patch_id))
  expect_identical(done$applied, 3L)
  expect_length(at_control_state(h)$current$rois, 3L)
})

test_that("(S11) session.load refuses to drop unsaved or staged edits and saves into its own directory", {
  h <- local_control(1)
  hub <- .control_hub(h)
  file.copy(at_example_path("tissue"), file.path(hub$root, "new.png"))
  at_export_qupflowr(at_example_project(), file.path(hub$root, "incoming", "handoff"),
                     formats = "qupath_geojson")
  cmd(h, "annotations.stage", list(payload_ref = "incoming/handoff"))
  err <- tryCatch(cmd(h, "session.load", list(images = list("new.png"))), error = function(e) e)
  expect_s3_class(err, "at_conflict_error")
  expect_identical(err$code, "UNSAVED_CHANGES")
  expect_identical(err$details$http_status, 409L)
  old_dir <- hub$session$out_dir
  expect_identical(.hub_generation(hub), 1L)
  ld <- cmd(h, "session.load", list(images = list("new.png"), discard_unsaved = TRUE))
  expect_match(ld$session_dir, "^sessions/session-")
  expect_identical(.hub_generation(hub), 2L)
  new_dir <- normalizePath(hub$session$out_dir, winslash = "/")
  expect_false(identical(new_dir, normalizePath(old_dir, winslash = "/")))
  expect_true(startsWith(new_dir, paste0(hub$root, "/")))
  cmd(h, "session.save", list())
  expect_true(file.exists(file.path(new_dir, "_session.rds")))
  expect_false(file.exists(file.path(old_dir, "_session.rds")))
  expect_true(.hub_entry_matches(hub, 1L, .hub_project(hub)))
  expect_false(.hub_entry_matches(hub, 1L, at_example_project()))
  expect_false(.hub_entry_matches(hub, 2L, .hub_project(hub)))
})

test_that("(S12) media types match exactly and NUL or non-UTF-8 bodies are rejected", {
  h <- local_control()
  good <- envelope("context.goto", list(queue_index = 2), "0")
  ok <- raw_post(h, "/v1/context/goto", good,
                 headers = list(`content-type` = "Application/JSON; charset=UTF-8"))
  expect_identical(ok$status, 200L)
  for (ct in c("application/jsonp", "application/json-seq", "application/json; charset=latin1",
               "text/json", "")) {
    expect_identical(raw_post(h, "/v1/context/goto", good, headers = list(`content-type` = ct))$status,
                     415L, label = ct)
  }
  hub <- .control_hub(h)
  hdr <- list(authorization = paste("Bearer", .control_tokens[[h$instance_id]]),
              `content-type` = "application/json")
  post <- function(body) {
    .control_handle_request(hub, "POST", "/v1/context/goto", headers = hdr, body = body,
                            transport = "in_process")
  }
  nul <- post(c(charToRaw('{"a":"'), as.raw(0L), charToRaw('"}')))
  expect_identical(nul$status, 422L)
  expect_identical(nul$body$error$code, "INVALID_JSON")
  latin <- post(c(charToRaw('{"a":"'), as.raw(0xffL), charToRaw('"}')))
  expect_identical(latin$body$error$code, "INVALID_JSON")
})

test_that("(S12) oversized or unauthenticated requests are refused before the body is read", {
  h <- local_control(1)
  hub <- .control_hub(h)
  tok <- .control_tokens[[h$instance_id]]
  app <- .control_httpuv_app(hub)
  req <- function(...) {
    list2env(list(REQUEST_METHOD = "POST", PATH_INFO = "/v1/context/goto",
                  HTTP_HOST = paste0("127.0.0.1:", hub$port), ...))
  }
  big <- app$onHeaders(req(HTTP_AUTHORIZATION = paste("Bearer", tok), CONTENT_TYPE = "application/json",
                           CONTENT_LENGTH = "5000000"))
  expect_identical(big$status, 413L)
  expect_match(big$body, "PAYLOAD_TOO_LARGE")
  expect_identical(app$onHeaders(req(CONTENT_LENGTH = "10"))$status, 401L)
  expect_identical(app$onHeaders(req(HTTP_AUTHORIZATION = paste("Bearer", tok), CONTENT_LENGTH = "10",
                                     HTTP_ORIGIN = "http://evil.example"))$status, 403L)
  expect_null(app$onHeaders(req(HTTP_AUTHORIZATION = paste("Bearer", tok), CONTENT_LENGTH = "10")))
})

test_that("(S13) evicted request records expire their idempotency keys instead of re-executing", {
  local_mocked_bindings(.control_max_requests = function() 2L)
  h <- local_control(3)
  hub <- .control_hub(h)
  cmd(h, "context.goto", list(queue_index = 2), rev = "0", idempotency_key = "k1")
  cmd(h, "context.goto", list(queue_index = 3), rev = "1", idempotency_key = "k2")
  cmd(h, "context.goto", list(queue_index = 1), rev = "2", idempotency_key = "k3")
  expect_lte(length(ls(hub$idempotency)), 2L)
  expect_lte(length(hub$request_order), 2L)
  err <- tryCatch(cmd(h, "context.goto", list(queue_index = 2), rev = "0", idempotency_key = "k1"),
                  error = function(e) e)
  expect_s3_class(err, "at_conflict_error")
  expect_identical(err$code, "IDEMPOTENCY_EXPIRED")
  expect_identical(at_control_state(h)$state_revision, "3")
  again <- cmd(h, "context.goto", list(queue_index = 1), rev = "2", idempotency_key = "k3")
  expect_true(attr(again, "response")$replayed)
})

test_that("(S13) large responses are stored and replayed in compact form", {
  local_mocked_bindings(.control_record_max_bytes = function() 2048)
  h <- local_control(1)
  mp <- cmd(h, "mask.preview", list(max_dim = 64, include_png = TRUE), idempotency_key = "mp-1",
            request_id = "mp-req")
  expect_true(nzchar(mp$png_base64))
  rec <- at_control_request_status(h, "mp-req")
  schema_ok(rec, "request-record")
  expect_null(rec$response$body$data$png_base64)
  expect_true(rec$response$body$response_truncated)
  again <- cmd(h, "mask.preview", list(max_dim = 64, include_png = TRUE), idempotency_key = "mp-1",
               request_id = "mp-req")
  expect_true(attr(again, "response")$replayed)
  expect_true(attr(again, "response")$response_truncated)
  expect_null(again$png_base64)
})

test_that("(S14) error messages sent to clients carry no absolute local paths", {
  h <- local_control(1)
  hub <- .control_hub(h)
  cmd(h, "export", list(destination = "dup", formats = list("qupath_geojson")))
  err <- tryCatch(cmd(h, "export", list(destination = "dup", formats = list("qupath_geojson"))),
                  error = function(e) e)
  expect_identical(err$code, "DESTINATION_EXISTS")
  msg <- conditionMessage(err)
  for (p in unique(c(hub$root, tempdir(), normalizePath(tempdir(), winslash = "/"), hub$session$out_dir))) {
    expect_false(grepl(p, msg, fixed = TRUE), label = p)
  }
  full <- hub$error_log[[length(hub$error_log)]]$message
  expect_true(grepl(hub$root, full, fixed = TRUE))
  expect_identical(.control_redact("Cannot read /Users/someone/data/slide 1.tif or '/opt/x/y.svs'."),
                   "Cannot read slide 1.tif or 'y.svs'.")
  expect_identical(.control_redact("at C:/Users/a/b.tif"), "at b.tif")
  expect_identical(.control_redact("see exports/dup and /v1"), "see exports/dup and /v1")
})

test_that("(S15) mask previews stay within a pixel budget and image ids are computed lazily", {
  h <- local_control(1)
  withr::local_options(hyperannotatR.control_mask_max_pixels = 100)
  err <- tryCatch(cmd(h, "mask.preview", list(level = 0)), error = function(e) e)
  expect_s3_class(err, "at_limit_error")
  expect_identical(err$code, "MASK_TOO_LARGE")
  expect_identical(err$details$http_status, 413L)
  withr::local_options(hyperannotatR.control_mask_max_pixels = NULL)
  expect_identical(cmd(h, "mask.preview", list(max_dim = 16))$level, 0L)

  d <- withr::local_tempdir()
  file.copy(at_example_path("tissue"), file.path(d, "a.png"))
  cube <- at_example_path("cube")
  s <- at_session(c(file.path(d, "a.png"), cube), out_dir = d)
  h2 <- at_control_start(s, serve = FALSE)
  withr::defer(at_control_stop(h2))
  hub2 <- .control_hub(h2)
  withr::local_options(hyperannotatR.control_hash_max_bytes = 1)
  st <- at_control_state(h2)
  expect_type(st$queue[[1]]$image_id, "character")
  expect_null(st$queue[[2]]$image_id)
  schema_ok(st, "state")
  withr::local_options(hyperannotatR.control_hash_max_bytes = NULL)
  img <- at_read_image(cube)
  # The id of an unvisited ENVI entry covers header and data, like a visited one.
  expect_identical(.hub_image_id(hub2, 2L), .image_id(img, .source_files(img)))
  g <- cmd(h2, "context.goto", list(image_id = .image_id(img, .source_files(img))))
  expect_identical(g$queue_index, 2L)
})

test_that("(S16) export destinations cannot escape the root through symbolic links", {
  skip_on_os("windows")
  h <- local_control(1)
  hub <- .control_hub(h)
  outside <- withr::local_tempdir()
  file.symlink(outside, file.path(hub$root, "exports"))
  err <- tryCatch(cmd(h, "export", list(destination = "x", formats = list("qupath_geojson"))),
                  error = function(e) e)
  expect_identical(err$code, "PATH_OUTSIDE_ROOT")
  expect_s3_class(err, "at_io_error")
  expect_length(list.files(outside, all.files = TRUE, no.. = TRUE), 0L)
  dir.create(file.path(hub$root, "training"))
  file.symlink(outside, file.path(hub$root, "training", "ds"))
  err2 <- tryCatch(cmd(h, "training.export", list(destination = "ds")), error = function(e) e)
  expect_identical(err2$code, "PATH_OUTSIDE_ROOT")
  expect_length(list.files(outside, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("(S17) event limits are validated, close ignores revisions and classes match local calls", {
  h <- local_control(1)
  hub <- .control_hub(h)
  tok <- .control_tokens[[h$instance_id]]
  get <- function(query) {
    .control_handle_request(hub, "GET", "/v1/events", query = query,
                            headers = list(authorization = paste("Bearer", tok)), transport = "in_process")
  }
  for (q in c("limit=abc", "limit=0", "limit=-1", "limit=1.5")) {
    res <- get(q)
    expect_identical(res$status, 422L, label = q)
    expect_identical(res$body$error$code, "VALIDATION_FAILED")
  }
  expect_identical(get("limit=5")$status, 200L)
  # Path errors are io errors, as when the function is called locally.
  err <- tryCatch(cmd(h, "annotations.stage", list(payload_ref = "../x")), error = function(e) e)
  expect_s3_class(err, "at_io_error")
  expect_identical(err$code, "PATH_OUTSIDE_ROOT")
  env <- rlang::current_env()
  old <- tryCatch(.control_raise(list(error = list(code = "PATH_OUTSIDE_ROOT", message = "m")), 403L, env),
                  error = function(e) e)
  expect_s3_class(old, "at_io_error")
  named <- tryCatch(.control_raise(list(error = list(code = "X", message = "m", class = "limit")), 422L, env),
                    error = function(e) e)
  expect_s3_class(named, "at_limit_error")
  internal <- tryCatch(.control_raise(list(error = list(code = "INTERNAL_ERROR", message = "m")), 500L, env),
                       error = function(e) e)
  expect_s3_class(internal, "at_io_error")
  # A stale revision does not block close.
  expect_true(cmd(h, "close", list(), rev = "999")$closing)
})

test_that("(S17) token files are created exclusively and nothing starts when they are refused", {
  skip_on_os("windows")
  root <- withr::local_tempdir()
  n_before <- length(ls(.control_registry))
  target <- file.path(root, "target")
  link <- file.path(root, "dangling")
  file.symlink(target, link)
  err <- tryCatch(at_control_start(at_example_session(1), root = root, token_file = link, serve = FALSE),
                  error = function(e) e)
  expect_identical(err$code, "DESTINATION_EXISTS")
  expect_false(file.exists(target))
  existing <- file.path(root, "tok-existing")
  writeLines("keep", existing)
  err <- tryCatch(at_control_start(at_example_session(1), root = root, token_file = existing, serve = FALSE),
                  error = function(e) e)
  expect_identical(err$code, "DESTINATION_EXISTS")
  expect_identical(readLines(existing), "keep")
  expect_identical(length(ls(.control_registry)), n_before)
  expect_length(list.files(root, pattern = "^annotatr-control-"), 0L)
  tok <- file.path(root, "tok")
  h <- at_control_start(at_example_session(1), root = root, token_file = tok, serve = FALSE)
  withr::defer(at_control_stop(h))
  expect_identical(file.info(tok)$mode, as.octmode("600"))
  expect_identical(readLines(tok), .control_tokens[[h$instance_id]])
})

test_that("no secure random source means no service: nothing is created, registered or listening", {
  skip_if_not_installed("httpuv")
  base <- withr::local_tempdir()
  root <- file.path(base, "control-root")
  tok <- file.path(base, "tok")
  n_before <- length(ls(.control_registry))
  port <- httpuv::randomPort(min = 20000L, max = 60000L, host = "127.0.0.1")
  local_mocked_bindings(.urandom_available = function() FALSE, .openssl_available = function() FALSE)
  err <- tryCatch(at_control_start(at_example_session(1), root = root, token_file = tok, port = port),
                  error = function(e) e)
  expect_s3_class(err, "at_capability_error")
  expect_identical(err$code, "CAPABILITY_UNAVAILABLE")
  expect_identical(length(ls(.control_registry)), n_before)
  expect_false(file.exists(tok))
  expect_false(dir.exists(root))
  # The port is still free: nothing was left listening.
  probe <- NULL
  expect_no_error(probe <- httpuv::startServer("127.0.0.1", port, list(
    call = function(req) list(status = 200L, headers = list(), body = "")
  )))
  if (!is.null(probe)) httpuv::stopServer(probe)
})

test_that("a project stored under another entry is a classified conflict that changes nothing", {
  h <- local_control(3)
  hub <- .control_hub(h)
  p1 <- .hub_project(hub)
  # Simulate the misfiling the identity check guards against: entry 1's
  # project saved as the checkpoint of entry 3.
  misfiled <- file.path(withr::local_tempdir(), "p1.rds")
  at_save_project(.lite_project(p1), misfiled)
  hub$session$manifest$project_path[3] <- misfiled
  rev <- at_control_state(h)$state_revision
  err <- tryCatch(cmd(h, "context.goto", list(queue_index = 3)), error = function(e) e)
  expect_s3_class(err, "at_conflict_error")
  expect_identical(err$code, "IDENTITY_MISMATCH")
  expect_identical(err$details$http_status, 409L)
  st <- at_control_state(h)
  expect_identical(st$state_revision, rev)
  expect_identical(st$current$queue_index, 1L)
  hub$session$manifest$project_path[3] <- NA_character_
  # The same check on save: entry 1's project in slot 2.
  hub$session$projects[[2]] <- p1
  status <- hub$annotation_status
  err <- tryCatch(cmd(h, "session.save", list()), error = function(e) e)
  expect_s3_class(err, "at_conflict_error")
  expect_identical(err$code, "IDENTITY_MISMATCH")
  expect_identical(at_control_state(h)$state_revision, rev)
  expect_identical(hub$annotation_status, status)
  expect_false(file.exists(file.path(hub$session$out_dir, "_session.rds")))
})
