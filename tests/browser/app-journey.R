# Full product UI and server with public synthetic TIFF inputs and a synthetic
# browser image URI. Native canvas encoding is deliberately isolated here.
# Run from the repository root; see tests/browser/README.md.
pkgload::load_all(quiet = TRUE)
fixture <- tempfile("annotatr-journey-"); dir.create(fixture)
paths <- file.path(fixture, c("missing.tif", "first.tif", "corrupt.tif", "decode.tif", "second.tif"))
for (p in paths) tiff::writeTIFF(matrix(seq_len(900) / 900, 30, 30), p)
replacement <- file.path(fixture, "replacement"); dir.create(replacement)
writeLines("corrupt", file.path(replacement, "bad.tif"))
s <- at_session(paths, labels = c("first", "second"), out_dir = file.path(fixture, "saved"), autosave = FALSE)
unlink(paths[1]); writeLines("corrupt", paths[3])

# Only add fixture content on the first materialisation. Normal navigation,
# retention, persistence and failure handling remain the actual app code.
with_fixture_content <- function(load) {
  force(load)
  function(session, i) {
    p <- load(session, i)
    if (is.null(session$projects[[i]])) {
      p <- at_add_roi(p, "annotations", at_roi_point(3, 3, "first", locked = TRUE))
      p <- at_add_layer(p, at_layer("locked", labels = "protected",
                                    style = at_style(locked = TRUE, colour = c(protected = "#008800"))))
      p <- at_add_roi(p, "locked", at_roi_rect(20, 20, 25, 25, "protected"))
      p <- at_add_layer(p, at_layer("hidden", labels = "hidden", style = at_style(visible = FALSE)))
      p <- at_add_roi(p, "hidden", at_roi_point(10, 10, "hidden"))
    }
    p
  }
}

product <- .app_server(s)
server <- function(input, output, session) {
  query <- shiny::isolate(shiny::parseQueryString(session$clientData$url_search))
  # ?resume=1 reopens the actual checkpoint through at_resume() in a new app.
  app <- if (identical(query$resume, "1")) .app_server(at_resume(file.path(s$out_dir, "_session.rds"))) else product
  rv <- app(input, output, session)
  rv$load_project <- with_fixture_content(shiny::isolate(rv$load_project))
  attempts <- shiny::reactiveVal(0L)
  writer <- shiny::isolate(rv$save_callback)
  rv$save_callback <- function(candidate, cursor) {
    attempts(shiny::isolate(attempts()) + 1L); writer(candidate, cursor)
  }
  output$fixture_state <- shiny::renderText(jsonlite::toJSON(list(
    ping = input$fixture_ping, tool = rv$tool, entry_id = rv$entry_id, revision = rv$revision,
    cursor = rv$cursor, ready = isTRUE(rv$display_ready),
    error = rv$display_error, saved = rv$saved, attempts = attempts(), active_layer = rv$active_layer,
    active_label = rv$active_label, autosave = rv$session$autosave,
    status = rv$session$manifest$status, recovery = !is.null(rv$recovery_queue),
    replacement = replacement, out_dir = rv$session$out_dir,
    undo = length(rv$undo), redo = length(rv$redo),
    rois = if (is.null(rv$project)) list() else lapply(rv$project$layers, function(layer) lapply(layer$rois, function(r)
      list(id = r$id, label = r$label, geometry = .sfg_to_geojson(r$geometry[[1]]), locked = isTRUE(r$attributes$locked)))),
    labels = if (is.null(rv$project)) list() else lapply(rv$project$layers, `[[`, "labels")
  ), auto_unbox = TRUE, null = "null"))
  shiny::outputOptions(output, "fixture_state", suspendWhenHidden = FALSE)
}
ui <- function(req) htmltools::tagList(
  .app_ui(),
  shiny::tags$details(shiny::tags$summary("Fixture state"), shiny::verbatimTextOutput("fixture_state"))
)
uri <- paste0("data:image/svg+xml,", utils::URLencode('<svg xmlns="http://www.w3.org/2000/svg" width="30" height="30"><rect width="30" height="30" fill="white"/></svg>', reserved = TRUE))
testthat::with_mocked_bindings(
  shiny::runApp(shiny::shinyApp(ui, server, onStart = function() shiny::addResourcePath("hyperannotatR-www", .app_www())),
                host = "127.0.0.1", port = as.integer(Sys.getenv("ANNOTATR_BROWSER_PORT", "5819")),
                launch.browser = FALSE),
  .image_data_uri = function(img, ...) if (basename(img$source) == "decode.tif") "data:image/png;base64,aW52YWxpZA==" else uri,
  .package = "hyperannotatR")
