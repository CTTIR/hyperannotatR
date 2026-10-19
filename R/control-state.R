# Control hub: the single source of truth for a controlled annotation session.
# It holds the session, a monotonic state revision, a bounded event ring
# buffer, request and idempotency records, and the view/selection/staging
# state an attached app mirrors. Tokens are never stored in the hub or the
# handle: they live in a package-private registry keyed by instance id, so a
# serialised handle cannot carry them.

.control_registry <- new.env(parent = emptyenv())
.control_tokens <- new.env(parent = emptyenv())

# The clock every TTL decision uses. A function so tests can move time forward
# without sleeping.
.control_now <- function() Sys.time()

# Retention limits for request records. Records (and the idempotency keys that
# point at them) beyond `.control_max_requests()` are evicted oldest first; a
# stored response larger than `.control_record_max_bytes()` is kept in compact
# form (scalar fields only, `response_truncated = TRUE`).
.control_max_requests <- function() 1000L
.control_record_max_bytes <- function() 65536

.new_control_hub <- function(session, root, ttl_seconds, host, port, read_only,
                             max_body_bytes) {
  hub <- new.env(parent = emptyenv())
  hub$instance_id <- paste0("instance-", .uuid())
  hub$session_id <- paste0("session-", .uuid())
  hub$protocol <- .contract$control
  hub$protocol_version <- .contract$version
  hub$created <- Sys.time()
  hub$expires_at <- hub$created + ttl_seconds
  hub$ttl_seconds <- ttl_seconds
  hub$pid <- Sys.getpid()
  hub$host <- host
  hub$port <- as.integer(port)
  hub$root <- root
  hub$read_only <- isTRUE(read_only)
  hub$max_body_bytes <- as.integer(max_body_bytes)
  hub$session <- session
  hub$revision <- 0L
  hub$event_seq <- 0L
  hub$events <- list()
  hub$requests <- new.env(parent = emptyenv())
  hub$request_order <- character()
  hub$idempotency <- new.env(parent = emptyenv())
  # Keys whose records were evicted, so a late retry is refused instead of
  # being executed a second time (bounded; see .hub_record_request()).
  hub$idempotency_evicted <- new.env(parent = emptyenv())
  hub$idempotency_evicted_order <- character()
  # Full, unredacted error messages for the owning process only; clients get
  # path-redacted messages (see .control_error_body()).
  hub$error_log <- list()
  # Incremented whenever the hub's session is replaced (session.load), so an
  # attached app can tell a project of the previous session from a current one.
  hub$generation <- 1L
  hub$view <- list(level = 0L, bounds = NULL, band_group = NULL, tool = "pan",
                   overlay = list(show = FALSE, mask_type = "labelled", alpha = 0.5))
  hub$selection <- character()
  hub$staged <- NULL
  hub$last_commit <- NULL
  hub$annotation_status <- "clean"
  hub$status <- "running"
  hub$last_origin <- "control"
  hub$apps <- new.env(parent = emptyenv())
  hub$image_ids <- new.env(parent = emptyenv())
  hub$server <- NULL
  hub$cancel_expiry <- NULL
  hub$manifest_path <- NA_character_
  class(hub) <- c("at_control_hub", class(hub))
  hub
}

# Current project, materialised lazily and kept in the hub session.
.hub_project <- function(hub) {
  i <- hub$session$cursor
  p <- hub$session$projects[[i]]
  if (is.null(p)) {
    p <- .materialize_project(hub$session, i)
    hub$session$projects[[i]] <- p
  }
  p
}

# Content-derived image id for a queue entry, cached by path, size and mtime.
# The id depends only on the file content (all source files of an ENVI pair),
# never on whether the entry has been visited, so it is stable across hubs.
# With `lazy = TRUE` an uncached id is computed only when the source files are
# at most `getOption("hyperannotatR.control_hash_max_bytes")` (default 256 MiB) in
# total; larger entries report NA (JSON null) until they are visited, so a
# state read never hashes a whole queue of slides synchronously.
.hub_image_id <- function(hub, i, lazy = FALSE) {
  path <- hub$session$manifest$path[i]
  info <- file.info(path)
  key <- paste(path, info$size, as.numeric(info$mtime), sep = "|")
  hit <- hub$image_ids[[key]]
  if (!is.null(hit)) {
    return(hit)
  }
  if (is.na(info$size)) {
    return(NA_character_)
  }
  p <- hub$session$projects[[i]]
  stub <- if (!is.null(p)) p$image else {
    list(backend = if (grepl("\\.hdr$", path, ignore.case = TRUE)) "envi" else "unknown",
         source = path, level_dims = list(), n_bands = NA_integer_)
  }
  if (lazy) {
    sizes <- vapply(.source_files(stub, hash = FALSE), function(f) f$size_bytes %||% NA_real_, numeric(1))
    cap <- as.numeric(getOption("hyperannotatR.control_hash_max_bytes", 256 * 1024^2))
    if (anyNA(sizes) || sum(sizes) > cap) {
      return(NA_character_)
    }
  }
  id <- .image_id(stub, .source_files(stub))
  assign(key, id, envir = hub$image_ids)
  id
}

# Record a state change: bump the revision and append an event.
.hub_bump <- function(hub, type, payload = list(), origin = list(kind = "control")) {
  hub$revision <- hub$revision + 1L
  hub$last_origin <- origin$kind
  .hub_event(hub, type, payload, origin)
}

# Append an event without changing the revision (e.g. a completed export).
.hub_event <- function(hub, type, payload = list(), origin = list(kind = "control")) {
  hub$event_seq <- hub$event_seq + 1L
  ev <- list(
    event_id = paste0(hub$instance_id, ":", hub$event_seq),
    seq = hub$event_seq,
    type = type,
    session_id = hub$session_id,
    state_revision = as.character(hub$revision),
    time = .utc_stamp(),
    origin = origin,
    payload = if (length(payload)) payload else .json_object()
  )
  hub$events <- c(hub$events, list(ev))
  cap <- .interop_limits()$control_max_events_buffer
  if (length(hub$events) > cap) {
    hub$events <- utils::tail(hub$events, cap)
  }
  invisible(ev)
}

.hub_event_cursor <- function(hub) {
  if (hub$event_seq == 0L) {
    return(paste0(hub$instance_id, ":0"))
  }
  paste0(hub$instance_id, ":", hub$event_seq)
}

# Events after a cursor. A cursor from another instance, or one older than the
# retained buffer, forces a full resync.
.hub_events_after <- function(hub, after = NULL, limit = 100L) {
  limit <- max(1L, min(as.integer(limit), .interop_limits()$control_max_events_page))
  events <- hub$events
  oldest <- if (length(events)) events[[1]]$seq else hub$event_seq + 1L
  resync <- FALSE
  from_seq <- oldest - 1L
  if (!is.null(after) && nzchar(after)) {
    inst <- sub(":[^:]*$", "", after)
    seq <- suppressWarnings(as.integer(sub("^.*:", "", after)))
    if (!identical(inst, hub$instance_id) || is.na(seq) || seq > hub$event_seq) {
      resync <- TRUE
    } else if (seq < oldest - 1L) {
      resync <- TRUE
    } else {
      from_seq <- seq
    }
  }
  sel <- Filter(function(e) e$seq > from_seq, events)
  more <- length(sel) > limit
  sel <- utils::head(sel, limit)
  next_cursor <- if (length(sel)) sel[[length(sel)]]$event_id else {
    if (!resync && !is.null(after) && nzchar(after)) after else .hub_event_cursor(hub)
  }
  list(events = sel, next_cursor = next_cursor, resync_required = resync,
       has_more = more, state_revision = as.character(hub$revision))
}

.roi_summary <- function(project, limit = 2000L) {
  rois <- list()
  for (nm in names(project$layers)) {
    for (r in project$layers[[nm]]$rois) {
      if (length(rois) >= limit) break
      bb <- as.numeric(sf::st_bbox(r$geometry))
      rois[[length(rois) + 1L]] <- list(
        roi_id = r$id, layer = nm, label = r$label, level = r$level,
        geom_type = as.character(sf::st_geometry_type(r$geometry)),
        bbox = list(xmin = bb[1], ymin = bb[2], xmax = bb[3], ymax = bb[4]),
        source = r$source, locked = isTRUE(r$attributes$locked),
        review_status = r$attributes$review_status %||% "unreviewed"
      )
    }
  }
  rois
}

# The explicit state snapshot returned by GET /v1/state.
.hub_state <- function(hub) {
  s <- hub$session
  m <- s$manifest
  proj <- tryCatch(.hub_project(hub), error = function(e) NULL)
  img <- if (is.null(proj)) NULL else proj$image
  n_total <- if (is.null(proj)) 0L else sum(vapply(proj$layers, function(L) length(L$rois), integer(1)))
  limit <- 2000L
  list(
    protocol = hub$protocol,
    protocol_version = hub$protocol_version,
    instance_id = hub$instance_id,
    session_id = hub$session_id,
    state_revision = as.character(hub$revision),
    event_cursor = .hub_event_cursor(hub),
    status = hub$status,
    mode = if (hub$read_only) "read_only" else "annotate",
    annotation_status = if (hub$read_only) "read_only" else hub$annotation_status,
    expires_at = .utc_stamp(hub$expires_at),
    coordinate_convention = .coordinate_convention(),
    queue = lapply(seq_len(nrow(m)), function(i) {
      list(entry_id = .session_entry_id(s, i), queue_index = i, name = m$name[i],
           status = m$status[i], n_rois = as.integer(m$n_rois[i]),
           image_id = .hub_image_id(hub, i, lazy = i != s$cursor))
    }),
    current = if (is.null(proj)) NULL else list(
      entry_id = .session_entry_id(s, s$cursor),
      queue_index = as.integer(s$cursor),
      annotation_revision = at_annotation_revision(proj),
      image = list(
        image_id = .hub_image_id(hub, s$cursor),
        source_name = basename(img$source),
        width = img$level_dims[[1]][1], height = img$level_dims[[1]][2],
        n_levels = img$n_levels, n_bands = img$n_bands,
        image_kind = .image_kind(img),
        value_unit = at_hsi_meta(img)$value_unit,
        calibration_status = at_hsi_meta(img)$calibration$status %||% "missing",
        wavelength_unit = img$wavelength_unit %||% NA_character_
      ),
      layers = unname(lapply(proj$layers, .layer_record)),
      rois = .roi_summary(proj, limit),
      rois_truncated = n_total > limit,
      mask_types = list("binary", "labelled", "multiclass")
    ),
    view = hub$view,
    selection = as.list(hub$selection),
    staged = if (is.null(hub$staged)) NULL else list(
      patch_id = hub$staged$patch_id, summary = hub$staged$summary,
      base_revision = hub$staged$base_revision, proposed_revision = hub$staged$proposed_revision
    ),
    last_commit = hub$last_commit,
    apps = list(connected = length(ls(hub$apps)))
  )
}

.hub_handshake <- function(hub) {
  caps <- at_interop_capabilities(target = c("app", "control"))
  list(
    protocol = hub$protocol,
    protocol_version = hub$protocol_version,
    annotatr_version = .pkg_version(),
    r_version = as.character(getRversion()),
    shiny_version = .pkg_version_or_na("shiny"),
    session_id = hub$session_id,
    instance_id = hub$instance_id,
    state_revision = as.character(hub$revision),
    capability_digest = caps$digest,
    capabilities = list(
      view = TRUE, selection = TRUE, annotation_stage = !hub$read_only,
      annotation_commit = !hub$read_only, mask_preview = TRUE, export = TRUE,
      training_export = TRUE, session_load = TRUE, session_save = !hub$read_only
    ),
    status = caps$control$status,
    coordinate_convention = .coordinate_convention(),
    geometry_formats = list("qupath_geojson", "geojson"),
    mask_formats = list("mask_tiff", "mask_npy"),
    event_cursor = .hub_event_cursor(hub),
    expires_at = .utc_stamp(hub$expires_at)
  )
}

.hub_health <- function(hub) {
  caps <- at_interop_capabilities(target = "control")
  list(
    protocol = hub$protocol,
    protocol_version = hub$protocol_version,
    annotatr_version = .pkg_version(),
    instance_id = hub$instance_id,
    status = hub$status,
    capability_digest = caps$digest,
    uptime_seconds = round(as.numeric(difftime(Sys.time(), hub$created, units = "secs")), 3),
    expires_at = .utc_stamp(hub$expires_at)
  )
}

# Store a request record, keeping the registry bounded. Evicting a record also
# evicts the idempotency keys that point at it; those keys are remembered (up
# to ten times the record limit) so a late retry gets IDEMPOTENCY_EXPIRED
# rather than being executed again.
.hub_record_request <- function(hub, record) {
  id <- record$request_id
  if (!exists(id, envir = hub$requests, inherits = FALSE)) {
    hub$request_order <- c(hub$request_order, id)
  }
  assign(id, record, envir = hub$requests)
  cap <- .control_max_requests()
  if (length(hub$request_order) > cap) {
    drop <- hub$request_order[seq_len(length(hub$request_order) - cap)]
    rm(list = drop, envir = hub$requests)
    hub$request_order <- utils::tail(hub$request_order, cap)
    keys <- ls(hub$idempotency, all.names = TRUE)
    stale <- keys[vapply(keys, function(k) hub$idempotency[[k]]$request_id %in% drop, logical(1))]
    if (length(stale)) {
      rm(list = stale, envir = hub$idempotency)
      for (k in stale) assign(k, TRUE, envir = hub$idempotency_evicted)
      hub$idempotency_evicted_order <- c(hub$idempotency_evicted_order, stale)
      keep <- 10L * cap
      if (length(hub$idempotency_evicted_order) > keep) {
        old <- hub$idempotency_evicted_order[seq_len(length(hub$idempotency_evicted_order) - keep)]
        rm(list = intersect(old, ls(hub$idempotency_evicted, all.names = TRUE)),
           envir = hub$idempotency_evicted)
        hub$idempotency_evicted_order <- utils::tail(hub$idempotency_evicted_order, keep)
      }
    }
  }
  invisible(record)
}

# A stored response small enough to keep: unchanged when it is at most
# `max_bytes`, otherwise only the small top-level data fields (each at most
# `max_bytes / 64`, 1 KiB by default) are kept and the
# envelope is marked `response_truncated = TRUE` (mask PNGs, operation lists
# and file inventories are dropped from the record; the live response is not
# affected).
.control_compact_response <- function(resp, max_bytes = .control_record_max_bytes()) {
  if (as.numeric(utils::object.size(resp)) <= max_bytes) {
    return(resp)
  }
  d <- resp$body$data
  if (is.list(d) && length(d)) {
    small <- vapply(d, function(v) as.numeric(utils::object.size(v)) <= max_bytes / 64, logical(1))
    d <- d[small]
  }
  resp$body$data <- if (is.list(d) && length(d)) d else .json_object()
  resp$body$response_truncated <- TRUE
  resp
}

# ---- Helpers for an attached app ---------------------------------------------

# The hub's session generation: an attached app records it when it adopts the
# hub's session and must not push projects or navigation from an older
# generation (the hub replaced its session in between, e.g. session.load).
.hub_generation <- function(hub) hub$generation

# Does `project` belong to queue entry `cursor` of the hub's current session?
# Compares the normalised image source with the manifest path, so an app can
# refuse to store a project in another image's slot.
.hub_entry_matches <- function(hub, cursor, project) {
  m <- hub$session$manifest
  cursor <- suppressWarnings(as.integer(cursor))
  if (is.null(project) || is.null(project$image) || length(cursor) != 1L || is.na(cursor) ||
      cursor < 1L || cursor > nrow(m)) {
    return(FALSE)
  }
  norm <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)
  identical(norm(project$image$source), norm(m$path[cursor]))
}
