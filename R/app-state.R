# Shared state transitions of the annotation app (internal).
#
# Every browser action carries the identity of the entry it was made on and
# the annotation revision it saw: `{entry_id, revision, payload}`. A
# transition applies only when that identity is still the live one, so a
# drawing, keystroke or button press queued before a navigation, reload or
# undo can never change another image or a newer state. Navigation is
# synchronous (snapshot, move, load), so the cursor and the live project never
# disagree. History stores annotation layers only, never image data, and is
# kept per queue entry.
#
# `rv` fields used here (see app-builder.R for the full list):
#   entry_id, revision          identity and revision of the live project
#   history, dirty              per-entry undo/redo stacks and unsaved flags
#   session_generation          queue replacement counter
#   loaded_generation           generation the live entry was loaded in
#   load_project, save_callback loader(session, i) and checkpoint writer
#   display_ready, display_error  canvas decode handshake
#   recovery_queue              previous queue retained after a folder load
#   store                       app-level store shared by tabs (see .app_store)

.state_revision <- function(project) {
  rev <- project$meta$annotation_revision %||% 0
  if (!is.numeric(rev) || length(rev) != 1L || is.na(rev) ||
      !is.finite(rev) || rev < 0 || rev != floor(rev)) {
    .at_abort("Invalid stored annotation revision.", code = "INVALID_REVISION")
  }
  as.numeric(rev)
}

# Entry ids of a queue. A session object built before entry identities
# existed (and not migrated by at_load_session()) gets them here, once, when
# the app opens it.
.state_identify <- function(sess) {
  m <- sess$manifest
  if (!"entry_id" %in% names(m)) {
    m$entry_id <- vapply(seq_len(nrow(m)), function(i) .state_new_entry_id(), character(1))
  }
  if (!"export_stem" %in% names(m)) {
    m$export_stem <- unname(vapply(m$entry_id, .entry_export_stem, character(1)))
  }
  sess$manifest <- m
  sess
}

.state_new_entry_id <- function() .new_identity_id("entry")

.state_init <- function(rv, load_project = NULL) {
  shiny::isolate({
    if (!isTRUE(rv$state_initialized)) {
      if (!is.null(rv$session)) rv$session <- .state_identify(rv$session)
      rv$history <- list()
      rv$dirty <- list()
      rv$history_limit <- 50L
      rv$session_generation <- rv$session_generation %||% 0
      rv$loaded_generation <- -1
      rv$entry_id <- NULL
      rv$revision <- 0
      rv$undo <- list(); rv$redo <- list()
      rv$save_error <- NULL
      rv$state_initialized <- TRUE
      if (!is.null(rv$project)) .state_adopt(rv, rv$project)
    }
    if (!is.null(load_project)) rv$load_project <- load_project
  })
  invisible(rv)
}

.state_adopt <- function(rv, project) {
  id <- rv$session$manifest$entry_id[rv$cursor]
  if (!is.null(project$meta$entry_id) && !identical(project$meta$entry_id, id)) {
    .at_abort("Project identity does not match the selected queue entry.",
              class = "conflict", code = "IDENTITY_MISMATCH")
  }
  rev <- .state_revision(project)
  project$meta$entry_id <- id
  project$meta$annotation_revision <- rev
  rv$entry_id <- id; rv$revision <- rev
  rv$project <- project
  rv$loaded_generation <- rv$session_generation
  history <- rv$history[[id]] %||% list(undo = list(), redo = list())
  rv$undo <- history$undo; rv$redo <- history$redo
  rv$active_layer <- names(project$layers)[1]
  rv$active_label <- if (length(project$layers)) .first_label(project$layers[[1]]$labels) else NULL
  rv$staged <- NULL
  rv$selection <- character()
  # A band view chosen for one image (e.g. cube bands 30/20/10) never carries
  # over to an image it does not fit.
  view <- .app_valid_view(project$image, rv$view)
  if (!is.null(rv$view) && is.null(view)) {
    .app_notify(sprintf("Display reset to natural colour: the band view does not apply to %s.",
                                    basename(project$image$source)), type = "message")
  }
  rv$view <- view
  rv$saved <- if (isTRUE(rv$dirty[[id]])) "unsaved" else "saved"
  invisible(TRUE)
}

.state_stamp <- function(rv) list(entry_id = rv$entry_id, revision = rv$revision)

.state_matches <- function(rv, event, require_project = TRUE) {
  (!require_project || !is.null(rv$project)) && !is.null(event) &&
    is.character(event$entry_id) && length(event$entry_id) == 1L &&
    identical(event$entry_id, rv$entry_id) &&
    identical(rv$entry_id, rv$session$manifest$entry_id[rv$cursor]) &&
    is.numeric(event$revision) && length(event$revision) == 1L &&
    is.finite(event$revision) && event$revision >= 0 &&
    event$revision == floor(event$revision) && isTRUE(event$revision == rv$revision)
}

# All browser actions carry the originating entry, revision and value snapshot.
# Trusted server transitions call .state_stamp() explicitly (or use the default).
.state_event <- function(rv, value, widget = FALSE, keyboard = FALSE, fields = NULL) {
  if (!is.list(value) || !all(c("entry_id", "revision", "payload") %in% names(value)) ||
      anyDuplicated(names(value))) return(NULL)
  if (!.state_matches(rv, value, require_project = FALSE)) return(NULL)
  if (!is.null(fields) && (!is.list(value$payload) ||
      !all(vapply(fields, function(field) {
        x <- value$payload[[field]]
        is.character(x) && length(x) == 1L && !is.na(x)
      }, logical(1))))) return(NULL)
  value
}

# The payload of a display-only widget event (probe, selection, viewport):
# envelopes must match the live entry; a bare value is accepted because these
# events never change annotations.
.state_view_payload <- function(rv, value) {
  if (is.list(value) && all(c("entry_id", "revision", "payload") %in% names(value))) {
    event <- if (identical(value$entry_id, rv$entry_id)) value else NULL
    return(event$payload)
  }
  value
}

.at_action <- function(inputId, label, ..., fields = NULL) {
  button <- shiny::actionButton(inputId, label, ...)
  htmltools::tagAppendAttributes(button, `data-at-action` = "true",
    `data-at-fields` = if (!is.null(fields)) jsonlite::toJSON(fields, auto_unbox = TRUE) else "{}")
}

# Protection is an app mutation rule, shared by every ingress and history path.
.state_protected <- function(before, after) {
  for (nm in names(before$layers)) {
    old <- before$layers[[nm]]; new <- after$layers[[nm]]
    if (isTRUE(old$style$locked) && !identical(old, new)) return(TRUE)
    for (roi in old$rois) if (isTRUE(roi$attributes$locked)) {
      matches <- Filter(function(r) identical(r$id, roi$id), new$rois)
      if (length(matches) != 1L || !identical(matches[[1]], roi)) return(TRUE)
    }
  }
  FALSE
}

.state_snapshot <- function(rv) {
  if (!.state_matches(rv, .state_stamp(rv))) return(invisible(FALSE))
  sess <- rv$session
  sess$projects[[rv$cursor]] <- rv$project
  sess$manifest$n_rois[rv$cursor] <- nrow(at_rois(rv$project))
  rv$session <- sess
  .app_store_put(rv, rv$cursor, rv$project)
  invisible(TRUE)
}

.state_history <- function(rv, undo, redo) {
  undo <- utils::tail(undo, rv$history_limit)
  redo <- utils::tail(redo, rv$history_limit)
  rv$history[[rv$entry_id]] <- list(undo = undo, redo = redo)
  rv$undo <- undo; rv$redo <- redo
}

.state_selection <- function(rv) {
  layers <- names(rv$project$layers)
  if (!length(layers)) {
    rv$active_layer <- NULL; rv$active_label <- NULL
    return(invisible(NULL))
  }
  if (!isTRUE(rv$active_layer %in% layers)) rv$active_layer <- layers[1]
  labels <- rv$project$layers[[rv$active_layer]]$labels
  if (!isTRUE(rv$active_label %in% labels)) {
    rv$active_label <- .first_label(labels)
  }
  invisible(NULL)
}

.state_changed <- function(rv, project, action = "edit") {
  rv$revision <- rv$revision + 1
  project$meta$entry_id <- rv$entry_id
  project$meta$annotation_revision <- rv$revision
  rv$project <- project
  rv$last_action <- action
  .state_selection(rv)
  rv$dirty[[rv$entry_id]] <- TRUE
  rv$saved <- "unsaved"
  .state_snapshot(rv)
  if (isTRUE(rv$session$autosave) && is.function(rv$save_callback)) .state_save(rv)
  invisible(TRUE)
}

# Apply `mutate` to the live project. Refused (FALSE) for a stale or
# unidentified event, an undisplayed image, read-only mode, a change to a
# locked layer or protected ROI, a no-op, or an error in `mutate` (reported
# instead of ending the Shiny session).
.state_mutate <- function(rv, mutate, event = .state_stamp(rv), action = "edit") {
  if (!.state_matches(rv, event) || identical(rv$display_ready, FALSE)) return(invisible(FALSE))
  if (isTRUE(rv$read_only)) {
    .app_notify("This session is read-only; the edit was not applied.", type = "warning")
    return(invisible(FALSE))
  }
  project <- tryCatch(mutate(rv$project), error = function(e) {
    .app_notify(paste("The edit failed:", .app_error_text(e)), type = "error")
    NULL
  })
  if (!inherits(project, "annot_project")) return(invisible(FALSE))
  if (.state_protected(rv$project, project)) {
    .app_notify("Locked layers and protected ROIs cannot be changed.", type = "warning")
    return(invisible(FALSE))
  }
  if (identical(project$layers, rv$project$layers)) return(invisible(FALSE))
  .state_history(rv, c(rv$undo, list(list(layers = rv$project$layers))), list())
  .state_changed(rv, project, action)
}

.state_undo <- function(rv, redo = FALSE, event = .state_stamp(rv)) {
  if (!.state_matches(rv, event) || isTRUE(rv$read_only)) return(invisible(FALSE))
  stack <- if (redo) rv$redo else rv$undo
  if (!length(stack)) return(invisible(FALSE))
  snapshot <- stack[[length(stack)]]
  candidate <- rv$project; candidate$layers <- snapshot$layers
  if (identical(rv$display_ready, FALSE) || .state_protected(rv$project, candidate)) return(invisible(FALSE))
  current <- list(layers = rv$project$layers)
  if (redo) .state_history(rv, c(rv$undo, list(current)), utils::head(stack, -1L))
  else .state_history(rv, utils::head(stack, -1L), c(rv$redo, list(current)))
  project <- rv$project
  project$layers <- snapshot$layers
  .state_changed(rv, project, if (redo) "redo" else "undo")
}

.state_load <- function(rv) {
  id <- rv$session$manifest$entry_id[rv$cursor]
  if (identical(rv$entry_id, id) &&
      identical(rv$loaded_generation, rv$session_generation)) return(invisible(TRUE))
  rv$entry_id <- id; rv$project <- NULL; rv$revision <- 0
  rv$display_ready <- FALSE; rv$display_error <- "Loading current image\u2026"
  rv$saved <- "unavailable"
  # A failed load is still an attempted load for this cursor/generation. Only
  # a new navigation/replacement retries it, not the following observer flush.
  rv$loaded_generation <- rv$session_generation
  rv$undo <- list(); rv$redo <- list()
  rv$staged <- NULL; rv$selection <- character()
  .app_store_cursor(rv)
  # Standalone module tests may supply only state, without an image loader.
  if (!is.function(rv$load_project)) return(invisible(FALSE))
  result <- tryCatch({
    .state_adopt(rv, rv$load_project(rv$session, rv$cursor))
  }, error = function(e) e)
  if (inherits(result, "error")) {
    rv$display_error <- paste("Could not load image:", .app_error_text(result))
    rv$session <- at_set_status(rv$session, rv$cursor, "skipped")
    .app_store_status(rv, rv$cursor, "skipped")
    .app_notify(paste("Could not load image:", .app_error_text(result)), type = "error")
    return(invisible(FALSE))
  }
  invisible(TRUE)
}

.state_navigate <- function(rv, target, event = .state_stamp(rv)) {
  # A failed image load has no live project; navigation must remain usable.
  if (!.state_matches(rv, event, require_project = FALSE)) return(invisible(FALSE))
  target <- max(1L, min(as.integer(target), nrow(rv$session$manifest)))
  .state_snapshot(rv)
  rv$session <- at_goto(rv$session, target)
  rv$cursor <- target
  .state_load(rv)
  invisible(TRUE)
}

.state_pending <- function(rv) {
  pending <- which(rv$session$manifest$status == "pending")
  next_entries <- pending[pending > rv$cursor]
  if (length(next_entries)) next_entries[1] else if (length(pending)) pending[1] else rv$cursor
}

.state_replace <- function(rv, sess, event = .state_stamp(rv)) {
  if (!.state_matches(rv, event, require_project = FALSE)) return(invisible(FALSE))
  .state_snapshot(rv)
  # Keep the complete in-memory queue (including dirty projects and history)
  # until it is explicitly restored or replaced after all edits are saved.
  if (!is.null(rv$recovery_queue) && any(vapply(rv$dirty, isTRUE, logical(1)))) {
    .app_notify("Restore the previous queue or save this queue before loading another folder.", type = "warning")
    return(invisible(FALSE))
  }
  if (is.null(rv$recovery_queue)) rv$recovery_queue <- list(session = rv$session,
    cursor = rv$cursor, history = rv$history, dirty = rv$dirty, project = rv$project,
    active_layer = rv$active_layer, active_label = rv$active_label)
  sess$autosave <- rv$session$autosave
  sess <- .state_identify(sess)
  rv$session <- sess; rv$cursor <- sess$cursor
  rv$history <- list(); rv$dirty <- list()
  rv$session_generation <- rv$session_generation + 1
  .app_store_replace(rv)
  .state_load(rv)
  invisible(TRUE)
}

.state_restore_queue <- function(rv, event = .state_stamp(rv)) {
  if (!.state_matches(rv, event, require_project = FALSE) || is.null(rv$recovery_queue)) return(invisible(FALSE))
  if (any(vapply(rv$dirty, isTRUE, logical(1)))) {
    .app_notify("Save the current queue's edits before restoring the previous queue.", type = "warning")
    return(invisible(FALSE))
  }
  old <- rv$recovery_queue
  rv$recovery_queue <- NULL; rv$session <- old$session; rv$cursor <- old$cursor
  rv$history <- old$history; rv$dirty <- old$dirty
  rv$session_generation <- rv$session_generation + 1
  .app_store_replace(rv)
  if (!is.null(old$project)) {
    .state_adopt(rv, old$project)
    rv$active_layer <- old$active_layer; rv$active_label <- old$active_label
    rv$display_ready <- FALSE; rv$display_error <- "Loading restored image\u2026"
  } else .state_load(rv)
  invisible(TRUE)
}

# Callback receives a candidate session and the original cursor. It must
# synchronously persist and return that session, or throw/return FALSE.
.state_save <- function(rv, complete = FALSE, advance = FALSE,
                        event = .state_stamp(rv)) {
  if (!.state_matches(rv, event) || isTRUE(rv$read_only)) return(invisible(FALSE))
  st <- rv$store
  if (!is.null(st) && !identical(st$generation, rv$session_generation)) {
    rv$save_error <- "This tab's queue was replaced in another tab; reload the page before saving."
    .app_notify(rv$save_error, type = "error", duration = NULL)
    return(invisible(FALSE))
  }
  .state_snapshot(rv)
  # The store also holds entries edited in other tabs of this app.
  candidate <- .app_store_candidate(rv)
  cursor <- rv$cursor
  if (complete) candidate <- at_set_status(candidate, cursor, "complete")
  rv$saved <- "saving"
  result <- tryCatch({
    if (!is.function(rv$save_callback)) {
      .at_fail("No save handler is available.", class = "capability", code = "CAPABILITY_UNAVAILABLE")
    }
    saved <- rv$save_callback(candidate, cursor)
    if (!inherits(saved, "annot_session")) {
      .at_fail("The save handler did not confirm persistence.", class = "io", code = "WRITE_FAILED")
    }
    saved
  }, error = function(e) e)
  if (inherits(result, "error")) {
    rv$dirty[[rv$entry_id]] <- TRUE
    rv$saved <- "unsaved"
    rv$save_error <- if (inherits(result, "at_conflict_error") && identical(result$code, "IDENTITY_MISMATCH")) {
      paste("Save refused: a project is stored under the wrong queue entry, so nothing was written.",
            "Reload the page; the last checkpoint is unchanged.")
    } else {
      paste("Save failed:", .app_error_text(result),
            "Check the output folder and retry Save before advancing.")
    }
    .app_notify(rv$save_error, type = "error", duration = NULL)
    return(invisible(FALSE))
  }
  rv$session <- result
  if (!is.null(st)) st$session <- result
  # One checkpoint holds every entry, so every entry is now saved.
  rv$dirty <- list()
  rv$saved <- "saved"; rv$save_error <- NULL
  rv$last_saved <- Sys.time()
  if (advance) .state_navigate(rv, cursor + 1L, event)
  invisible(TRUE)
}

.state_status <- function(rv, status, event = .state_stamp(rv)) {
  if (!.state_matches(rv, event) || isTRUE(rv$read_only)) return(invisible(FALSE))
  rv$session <- at_set_status(rv$session, rv$cursor, status)
  .app_store_status(rv, rv$cursor, status)
  rv$dirty[[rv$entry_id]] <- TRUE; rv$saved <- "unsaved"
  if (isTRUE(rv$session$autosave) && is.function(rv$save_callback)) .state_save(rv)
  invisible(TRUE)
}

# A notification in the running Shiny session (none when a transition runs
# outside one, e.g. from a script or test).
.app_notify <- function(...) {
  if (!is.null(shiny::getDefaultReactiveDomain())) shiny::showNotification(...)
  invisible(NULL)
}

# A condition message as plain text for the page: no ANSI styling or cli
# bullet glyphs, and without the "i" hints written for console users (such as
# pointing to at_example_path()), which do not apply inside the app.
.app_error_text <- function(cnd) {
  lines <- trimws(strsplit(cli::ansi_strip(conditionMessage(cnd)), "\n", fixed = TRUE)[[1]])
  lines <- lines[nzchar(lines) & !grepl("^(\u2139|i) ", lines)]
  lines <- sub("^(\u2716|\u2715|\u00d7|x|!|\u2022|\\*|\u2192|>|\u2714|v) ", "", lines)
  paste(lines, collapse = " ")
}

# ---- App store: one in-memory queue per app object ------------------------------
#
# Every Shiny session of one app object starts from, and writes its entries
# into, a shared store, so a page reload or a second tab continues from the
# latest in-memory state instead of the session the app was built with. Edits
# are merged per entry; two tabs editing the same image keep the last edit. A
# tab whose queue was replaced elsewhere (newer generation) stops writing.

.app_store <- function(sess) {
  st <- new.env(parent = emptyenv())
  st$session <- .state_identify(sess)
  st$generation <- 0
  st$written <- character()
  st
}

.app_live_store <- function(rv) {
  st <- rv$store
  if (is.null(st) || !identical(st$generation, rv$session_generation %||% 0)) NULL else st
}

.app_store_put <- function(rv, i, project) {
  st <- .app_live_store(rv)
  if (is.null(st) || i > length(st$session$projects) ||
      !identical(st$session$manifest$entry_id[i], rv$session$manifest$entry_id[i])) {
    return(invisible(FALSE))
  }
  st$session$projects[[i]] <- project
  st$session$manifest$n_rois[i] <- nrow(at_rois(project))
  invisible(TRUE)
}

.app_store_status <- function(rv, i, status) {
  st <- .app_live_store(rv)
  if (!is.null(st) && i <= nrow(st$session$manifest)) st$session$manifest$status[i] <- status
  invisible(NULL)
}

.app_store_cursor <- function(rv) {
  st <- .app_live_store(rv)
  if (!is.null(st)) st$session <- at_goto(st$session, rv$cursor)
  invisible(NULL)
}

.app_store_replace <- function(rv) {
  st <- rv$store
  if (!is.null(st)) {
    st$session <- rv$session
    st$generation <- rv$session_generation
  }
  invisible(NULL)
}

# The session to checkpoint: this tab's session (its settings and cursor) with
# every entry's project, status and ROI count from the store, which holds the
# latest change of any tab, this one included.
.app_store_candidate <- function(rv) {
  candidate <- rv$session
  st <- .app_live_store(rv)
  if (is.null(st) || !identical(st$session$manifest$entry_id, candidate$manifest$entry_id)) {
    return(candidate)
  }
  candidate$projects <- st$session$projects
  for (col in c("status", "n_rois")) candidate$manifest[[col]] <- st$session$manifest[[col]]
  candidate
}

# ---- Saving -------------------------------------------------------------------

# Identity and geometry of every ROI held by a session's projects.
.session_roi_keys <- function(s) {
  unlist(lapply(s$projects, function(p) {
    if (is.null(p)) return(character())
    unlist(lapply(p$layers, function(L) {
      vapply(L$rois, function(r) paste(L$name, r$id, .roi_record(r, L$name)$geometry_sha256),
             character(1))
    }), use.names = FALSE)
  }), use.names = FALSE)
}

# Before this app first replaces an existing `_session.rds` of a queue, keep a
# timestamped copy when that file holds another queue or any ROI the new
# checkpoint lacks, so a relaunch over the same folder or a stale tab cannot
# erase work.
.app_backup_session <- function(store, candidate) {
  path <- file.path(candidate$out_dir, "_session.rds")
  key <- paste(normalizePath(path, winslash = "/", mustWork = FALSE),
               paste(candidate$manifest$entry_id, collapse = ","))
  if (!is.null(store) && key %in% store$written) {
    return(invisible(NULL))
  }
  if (file.exists(path)) {
    old <- tryCatch(readRDS(path), error = function(e) NULL)
    keep <- !inherits(old, "annot_session") ||
      !identical(as.character(old$manifest$path), as.character(candidate$manifest$path)) ||
      !all(.session_roi_keys(old) %in% .session_roi_keys(candidate))
    if (keep) {
      bak <- file.path(candidate$out_dir, sprintf("_session-%s.previous.rds",
                                                  format(Sys.time(), "%Y%m%d-%H%M%OS3")))
      if (file.copy(path, bak, overwrite = FALSE)) {
        .app_notify(sprintf("The previous session file was kept as %s.", basename(bak)),
                                type = "message")
      }
    }
  }
  if (!is.null(store)) store$written <- c(store$written, key)
  invisible(NULL)
}

# Persist `candidate` as one atomic checkpoint (every entry's project, then
# the session file) and return it with its project paths.
.app_save_checkpoint <- function(candidate, cursor) .save_checkpoint(candidate, cursor)
