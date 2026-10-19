# Two-way synchronisation between an attached app and its control hub. The hub
# is the source of truth: controller commands change the hub and the app
# follows it through a revision poll; user edits in the app are pushed into the
# hub with origin "app" so controllers see them as events. Internal.
#
# Identity rules:
#   * the app pushes only a live, consistent project (.state_matches) to the
#     hub entry under the cursor, only when its image is that entry's file
#     (.hub_entry_matches) and only while app and hub hold the same session
#     generation;
#   * a hub change made by anyone else (a controller or another tab) is applied
#     by reopening the entry from the hub, with a new annotation revision, so a
#     gesture made on the previous content is rejected;
#   * an app edit never overwrites an entry that someone else changed since the
#     app opened it; the app shows the hub's version instead.

# The hub's session generation (incremented by session.load) and its queue;
# together they tell whether app and hub show the same session.
.hub_session_key <- function(hub) {
  list(generation = hub$generation %||% 1L, paths = as.character(hub$session$manifest$path))
}

.same_queue <- function(rv_session, hub) {
  identical(as.character(rv_session$manifest$path), as.character(hub$session$manifest$path))
}

# Push app-side changes (the live project, navigation, queue statuses) into
# the hub. `project` is NULL unless it is the live, consistent project of
# entry `cursor`; `base` is that entry's annotation revision when the app
# opened it (or last synced). Returns the revisions it created and whether a
# conflicting hub change blocked the project push.
.hub_push_from_app <- function(hub, rv_session, cursor, project, app_id, base = NULL) {
  out <- list(revisions = integer(), conflict = FALSE, pushed = FALSE)
  if (!identical(hub$status, "running") || !.same_queue(rv_session, hub)) {
    return(out)
  }
  origin <- list(kind = "app", request_id = app_id)
  bump <- function(type, payload) {
    .hub_bump(hub, type, payload, origin)
    out$revisions <<- c(out$revisions, hub$revision)
  }
  cursor <- suppressWarnings(as.integer(cursor))
  if (!is.null(project) && .hub_entry_matches(hub, cursor, project)) {
    current <- hub$session$projects[[cursor]]
    cur_rev <- if (is.null(current)) NA_character_ else at_annotation_revision(current)
    new_rev <- at_annotation_revision(project)
    if (!identical(cur_rev, new_rev)) {
      if (!is.null(current) && !is.null(base) && !identical(cur_rev, base)) {
        out$conflict <- TRUE
      } else {
        hub$session$projects[[cursor]] <- project
        hub$session$manifest$n_rois[cursor] <- nrow(at_rois(project))
        if (!identical(hub$annotation_status, "staged")) hub$annotation_status <- "unsaved"
        bump("annotations.edited",
             list(queue_index = cursor, entry_id = .session_entry_id(hub$session, cursor),
                  annotation_revision = new_rev))
        out$pushed <- TRUE
      }
    }
  }
  if (length(cursor) == 1L && !is.na(cursor) && !identical(cursor, as.integer(hub$session$cursor))) {
    hub$session <- at_goto(hub$session, cursor)
    hub$selection <- character()
    hub$staged <- NULL
    bump("image.changed", list(queue_index = cursor, entry_id = .session_entry_id(hub$session, cursor)))
  }
  status <- as.character(rv_session$manifest$status)
  changed <- which(status != as.character(hub$session$manifest$status))
  for (i in changed) {
    hub$session$manifest$status[i] <- status[i]
    bump("queue.status_changed",
         list(queue_index = i, entry_id = .session_entry_id(hub$session, i), status = status[i]))
  }
  out
}

.control_app_attach <- function(hub, rv, session) {
  # A random id: the Shiny session token is a credential and is not published.
  app_id <- paste0("app-", .uuid())
  assign(app_id, list(connected_at = .utc_stamp()), envir = hub$apps)
  .hub_event(hub, "app.connected", list(app_id = app_id))
  synced <- hub$revision
  own <- integer()
  key <- .hub_session_key(hub)
  last_view <- hub$view
  last_selection <- hub$selection
  last_staged <- hub$staged
  # Annotation revision of each entry when the app opened it (or last synced
  # it): an app edit is pushed only over that revision.
  base <- new.env(parent = emptyenv())
  session$onSessionEnded(function() {
    if (exists(app_id, envir = hub$apps, inherits = FALSE)) rm(list = app_id, envir = hub$apps)
    .hub_event(hub, "app.disconnected", list(app_id = app_id))
  })

  # Reopen the entry under the hub's cursor from the hub session. The new
  # revision is above the previous one, so the widget re-renders and stale
  # gestures are rejected.
  reopen <- function() {
    old <- shiny::isolate(rv$revision) %||% 0
    entry <- shiny::isolate(rv$entry_id)
    if (!is.null(entry)) rv$history[[entry]] <- NULL
    rv$loaded_generation <- -1
    .state_load(rv)
    p <- shiny::isolate(rv$project)
    if (!is.null(p) && shiny::isolate(rv$revision) <= old) {
      p$meta$annotation_revision <- old + 1
      rv$project <- p
      rv$revision <- old + 1
    }
    if (!is.null(p)) assign(shiny::isolate(rv$entry_id), at_annotation_revision(p), envir = base)
  }

  apply_hub <- function() {
    if (!"entry_id" %in% names(hub$session$manifest)) hub$session <- .state_identify(hub$session)
    new_key <- .hub_session_key(hub)
    replaced <- !identical(new_key, key)
    key <<- new_key
    cursor <- as.integer(hub$session$cursor)
    proj <- shiny::isolate(rv$project)
    hub_proj <- if (!replaced && cursor <= length(hub$session$projects)) hub$session$projects[[cursor]]
    entry_changed <- !is.null(hub_proj) && !is.null(proj) &&
      identical(cursor, as.integer(shiny::isolate(rv$cursor))) &&
      !identical(at_annotation_revision(hub_proj), at_annotation_revision(proj))
    rv$session <- hub$session
    if (replaced) {
      rv$history <- list(); rv$dirty <- list(); rv$recovery_queue <- NULL
      rv$session_generation <- shiny::isolate(rv$session_generation) + 1
      for (k in ls(base)) rm(list = k, envir = base)
      rv$cursor <- cursor
      reopen()
    } else if (!identical(cursor, as.integer(shiny::isolate(rv$cursor)))) {
      rv$cursor <- cursor
      .state_load(rv)
    } else if (entry_changed) {
      shiny::showNotification("This image was changed by the control service; showing its version.",
                              type = "message")
      reopen()
    }
    if (!identical(hub$staged, last_staged) || replaced) {
      last_staged <<- hub$staged
      rv$staged <- hub$staged
    }
    if (identical(hub$annotation_status, "committed") && !is.null(hub$last_commit)) {
      rv$last_commit <- hub$last_commit
      rv$last_action <- "commit"
    }
    if (!identical(hub$selection, last_selection)) {
      last_selection <<- hub$selection
      rv$selection <- as.character(hub$selection)
    }
    # View fields change only through controller commands; apply them only
    # when they did change, so a revision for an edit never resets the user's
    # tool, band view or overlay.
    if (!identical(hub$view, last_view)) {
      old <- last_view
      last_view <<- hub$view
      v <- hub$view
      if (!identical(v$band_group, old$band_group)) {
        bg <- v$band_group
        view <- if (is.null(bg)) NULL else list(operation = bg$operation,
                                                bands = as.integer(unlist(bg$bands)),
                                                params = bg$params)
        img <- shiny::isolate(rv$project)$image
        rv$view <- if (is.null(img)) view else .app_valid_view(img, view)
      }
      if (!identical(v$tool, old$tool) && !is.null(v$tool)) rv$tool <- v$tool
      if (!identical(v$overlay, old$overlay)) {
        rv$overlay_on <- isTRUE(v$overlay$show)
        rv$overlay_alpha <- v$overlay$alpha %||% 0.5
        if (!is.null(v$overlay$mask_type)) rv$mask_type <- v$overlay$mask_type
      }
      if (!identical(v$bounds, old$bounds) && !is.null(v$bounds)) {
        rv$fit_bounds <- as.numeric(unlist(v$bounds))
      }
    }
    invisible(NULL)
  }

  poll <- shiny::reactivePoll(250, session, checkFunc = function() hub$revision,
                              valueFunc = function() hub$revision)
  # Hub -> app: apply every revision that this app did not make itself.
  shiny::observeEvent(poll(), {
    rev <- poll()
    if (rev <= synced) return()
    others <- setdiff(seq.int(synced + 1L, rev), own)
    synced <<- rev
    own <<- own[own > rev]
    if (length(others) == 0L) return()
    apply_hub()
  }, ignoreInit = TRUE)

  # Record the base revision whenever an entry is opened (before any edit).
  shiny::observeEvent(list(rv$entry_id, rv$session_generation), {
    if (.state_matches(rv, .state_stamp(rv))) {
      assign(rv$entry_id, at_annotation_revision(rv$project), envir = base)
    }
  }, ignoreNULL = FALSE)

  # App -> hub, for the live project and the queue it belongs to.
  shiny::observeEvent(list(rv$project, rv$revision, rv$entry_id, rv$session, rv$cursor), {
    # The hub replaced its session since the app adopted it: wait for the poll
    # to apply the new one rather than pushing into it.
    if (!identical(key, .hub_session_key(hub)) || !.same_queue(rv$session, hub)) return()
    live <- .state_matches(rv, .state_stamp(rv))
    proj <- if (live) rv$project else NULL
    b <- if (live) base[[rv$entry_id]] else NULL
    res <- .hub_push_from_app(hub, rv$session, rv$cursor, proj, app_id, base = b)
    own <<- c(own, res$revisions)
    if (isTRUE(res$pushed)) assign(rv$entry_id, at_annotation_revision(proj), envir = base)
    if (isTRUE(res$conflict)) {
      shiny::showNotification(
        "The control service changed this image since you opened it; your last edit was not synced. Showing its version.",
        type = "warning", duration = NULL)
      rv$session <- hub$session
      reopen()
    }
  }, ignoreInit = TRUE)
  invisible(app_id)
}

mod_control_status_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::uiOutput(ns("status"))
}

mod_control_status_server <- function(id, rv, hub = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    output$status <- shiny::renderUI({
      if (is.null(hub)) return(NULL)
      shiny::invalidateLater(1000)
      shiny::div(
        class = "at-progress at-control", role = "status",
        sprintf("control: %s | revision %d | %s", hub$status, hub$revision,
                if (isTRUE(hub$read_only)) "read-only" else "annotate")
      )
    })
  })
}
