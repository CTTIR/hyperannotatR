# The canvas is JavaScript; here it is tested at the R contract boundary
# (widget construction, tile source, proxy messages, coordinate handling).
skip_if_not_installed("htmlwidgets")

mock_session <- function() {
  msgs <- list()
  list(
    session = list(sendCustomMessage = function(type, message) {
      msgs[[length(msgs) + 1L]] <<- list(type = type, message = message)
    }),
    messages = function() msgs
  )
}

test_that("at_canvas returns a configured htmlwidget", {
  skip_if_not_installed("tiff")
  w <- at_canvas(at_example_image("tissue"))
  expect_s3_class(w, "htmlwidget")
  expect_true(all(c("tileSource", "annotations", "tool") %in% names(w$x)))
  expect_identical(w$x$annotations$type, "FeatureCollection")
})

test_that("at_canvas seeds annotations from a project", {
  skip_if_not_installed("tiff")
  w <- at_canvas(at_example_image("tissue"), project = at_example_project())
  expect_length(w$x$annotations$features, 3L)
})

test_that("at_tile_source describes the image", {
  ts <- at_tile_source(small_image(), embed = FALSE)
  expect_identical(ts$width, 100L)
  expect_identical(ts$height, 100L)
  expect_identical(ts$maxLevel, 2L)
  expect_identical(ts$nBands, 3L)
})

test_that("proxy setters send correctly-addressed messages", {
  m <- mock_session()
  px <- at_canvas_proxy("cv", session = m$session)
  at_canvas_set_tool(px, "polygon")
  at_canvas_set_band(px, 2L)
  at_canvas_fit(px, c(0, 0, 50, 50))
  msgs <- m$messages()
  types <- vapply(msgs, `[[`, character(1), "type")
  expect_identical(types, c("atcanvas-set_tool", "atcanvas-set_band", "atcanvas-fit_bounds"))
  expect_true(all(vapply(msgs, function(x) identical(x$message$id, "cv"), logical(1))))
  expect_identical(msgs[[1]]$message$tool, "polygon")
})

test_that("at_canvas_set_annotations sends a FeatureCollection", {
  skip_if_not_installed("tiff")
  m <- mock_session()
  px <- at_canvas_proxy("cv", session = m$session)
  at_canvas_set_annotations(px, at_example_project())
  msg <- m$messages()[[1]]
  expect_identical(msg$type, "atcanvas-set_annotations")
  expect_identical(msg$message$annotations$type, "FeatureCollection")
})

test_that("tools validate against the allowed set", {
  m <- mock_session()
  px <- at_canvas_proxy("cv", session = m$session)
  expect_error(at_canvas_set_tool(px, "bogus"), "must be one of")
})

test_that("drawn level-0 coordinates rasterise to the drawn pixels", {
  # A feature emitted by the JS at level-0 pixels (2,2)-(5,5) must land on
  # mask rows/cols 3-5 (the coordinate contract across the JS -> R boundary).
  g <- sf::st_polygon(list(rbind(c(2, 2), c(5, 2), c(5, 5), c(2, 5), c(2, 2))))
  roi <- at_roi_from_sf(sf::st_sfc(g, crs = sf::NA_crs_), label = "drawn")
  idx <- which(as.matrix(at_mask(roi, "binary", dims = c(10, 10))), arr.ind = TRUE)
  expect_identical(sort(unique(idx[, 1])), 3:5)
  expect_identical(sort(unique(idx[, 2])), 3:5)
})

test_that("the widget JavaScript makes no external requests", {
  js <- readLines(system.file("htmlwidgets", "atcanvas.js", package = "hyperannotatR"))
  expect_false(any(grepl("https?://", js)))
})

test_that("Shiny output/render helpers are defined", {
  expect_true(is.function(atCanvasOutput))
  expect_true(is.function(renderAtCanvas))
})

# ---- Display contract: image errors, view fallback, styled features --------

pixel_image <- function(nb = 3L, w = 40L, h = 30L) {
  arr <- array(seq_len(w * h * nb) %% 251, dim = c(h, w, nb))
  new_annot_image(source = file.path(tempdir(), "px.tif"), backend = "raster",
                  dims = c(w, h), n_levels = 1L, level_dims = list(c(w, h)),
                  n_bands = nb, handle = list(data = arr))
}

test_that("an image that cannot be encoded says why instead of showing nothing (W3)", {
  skip_if_not_installed("magick")
  img <- pixel_image()
  local_mocked_bindings(.view_display_array = function(...) stop("decoder exploded"))
  res <- .image_data_uri_result(img)
  expect_null(res$uri)
  expect_match(res$error, "decoder exploded")
  expect_null(.image_data_uri(img))  # the encoding seam keeps its URI-or-NULL contract
  ts <- at_tile_source(img)
  expect_null(ts$dataUri)
  expect_match(ts$displayError, "Could not encode the image for display \\(decoder exploded\\)")
})

test_that("a missing magick explains the display requirement", {
  img <- pixel_image()
  src <- at_tile_source
  environment(src) <- list2env(list(requireNamespace = function(...) FALSE,
                                    .image_data_uri = function(...) NULL),
                               parent = environment(at_tile_source))
  ts <- src(img)
  expect_null(ts$dataUri)
  expect_match(ts$displayError, "requires package magick")
})

test_that("a view that does not fit the image falls back to natural colour (W3)", {
  skip_if_not_installed("magick")
  img <- pixel_image(nb = 3L)
  ts <- at_tile_source(img, view = list(operation = "rgb", bands = c(30L, 20L, 10L)))
  expect_match(ts$dataUri, "^data:image/png;base64,")
  expect_null(ts$displayError)
  expect_true(is.character(ts$viewError) && nzchar(ts$viewError))
  ok <- at_tile_source(img, view = list(operation = "rgb", bands = c(3L, 2L, 1L)))
  expect_null(ok$viewError)
})

test_that("canvas features carry label colours, lock state and layer order (W19)", {
  .reset_id_counter()
  img <- small_image()
  a <- at_layer("a", labels = c("x", "y"), style = at_style(colour = c(x = "red", y = "#0000FF"), z = 2L))
  a <- at_layer_add(a, at_roi_rect(0, 0, 5, 5, label = "x"))
  a <- at_layer_add(a, at_roi_rect(5, 5, 9, 9, label = "y"))
  b <- at_layer("b", labels = "z", style = at_style(locked = TRUE, z = 1L, fill_alpha = 0.6))
  b <- at_layer_add(b, at_roi_rect(1, 1, 3, 3, label = "z"))
  hidden <- at_layer("h", labels = "q", style = at_style(visible = FALSE))
  hidden <- at_layer_add(hidden, at_roi_rect(1, 1, 2, 2, label = "q"))
  proj <- at_project(img, list(a, b, hidden))
  fc <- .canvas_features(proj)
  props <- lapply(fc$features, `[[`, "properties")
  # Hidden layer dropped; z = 1 drawn (and hit-tested) below z = 2.
  expect_identical(vapply(props, `[[`, "", "layer"), c("b", "a", "a"))
  expect_identical(vapply(props, `[[`, "", "colour")[2:3], c("#FF0000", "#0000FF"))
  expect_true(all(grepl("^#[0-9A-F]{6}$", vapply(props, `[[`, "", "colour"))))
  expect_identical(vapply(props, `[[`, logical(1), "locked"), c(TRUE, FALSE, FALSE))
  expect_equal(props[[1]]$fill_alpha, 0.6)
  # The widget and the proxy use the same styled features.
  skip_if_not_installed("magick")
  w <- at_canvas(pixel_image(), project = proj)
  expect_identical(w$x$annotations$features[[2]]$properties$colour, "#FF0000")
  m <- mock_session()
  at_canvas_set_annotations(at_canvas_proxy("cv", session = m$session), proj)
  expect_length(m$messages()[[1]]$message$annotations$features, 3L)
})

test_that("a project without ROIs gives an empty feature list", {
  fc <- .canvas_features(at_project(small_image(), at_layer("l")))
  expect_identical(fc$type, "FeatureCollection")
  expect_length(fc$features, 0L)
})

test_that("renders and annotation updates carry the entry identity", {
  skip_if_not_installed("magick")
  proj <- at_project(pixel_image(), at_layer("l"))
  expect_null(at_canvas(pixel_image(), project = proj)$x$identity)
  proj$meta$entry_id <- "entry-7"
  proj$meta$annotation_revision <- 3
  expect_identical(at_canvas(pixel_image(), project = proj)$x$identity,
                   list(entry_id = "entry-7", revision = 3))
  m <- mock_session()
  at_canvas_set_annotations(at_canvas_proxy("cv", session = m$session), proj)
  expect_identical(m$messages()[[1]]$message$identity, list(entry_id = "entry-7", revision = 3))
})

test_that("proxies created inside a module address the namespaced output", {
  m <- mock_session()
  sess <- m$session
  sess$ns <- shiny::NS("mod")
  expect_identical(at_canvas_proxy("canvas", session = sess)$id, "mod-canvas")
  expect_identical(at_canvas_proxy("mod-canvas", session = sess)$id, "mod-canvas")
  sess$ns <- shiny::NS(NULL)
  expect_identical(at_canvas_proxy("canvas", session = sess)$id, "canvas")
  expect_identical(at_canvas_proxy("canvas", session = m$session)$id, "canvas")
})

test_that("proxies in a real module session reach the module's canvas", {
  skip_if_not_installed("shiny")
  sent <- NULL
  rendered <- NULL
  mod <- function(id) shiny::moduleServer(id, function(input, output, session) {
    sent <<- at_canvas_proxy("canvas", session = session)$id
    rendered <<- session$ns("canvas")  # the element id renderAtCanvas() fills
  })
  shiny::testServer(mod, {}, args = list(id = "canvas"))
  expect_identical(sent, "canvas-canvas")
  expect_identical(sent, rendered)
})

test_that("bitfield overlays colour every membership (M6); background stays clear", {
  skip_if_not_installed("magick")
  m <- matrix(0L, 4, 4)
  m[1, 1] <- 1L   # class a only
  m[1, 2] <- 2L   # class b only
  m[1, 3] <- 3L   # a and b
  lg <- tibble::tibble(value = c(1L, 2L), label = c("a", "b"), layer = NA_character_,
                       roi_id = NA_character_, n_px = c(2L, 2L),
                       colour = c("#FF0000", "#0000FF"))
  decode <- function(uri) {
    raw <- jsonlite::base64_dec(sub("^data:image/png;base64,", "", uri))
    as.integer(magick::image_data(magick::image_read(raw), "rgba"))  # [y, x, channel]
  }
  px <- decode(.mask_data_uri(.new_annot_mask(m, lg, 0L, c(4L, 4L), "multiclass", encoding = "bitfield")))
  expect_identical(px[1, 1, ], c(255L, 0L, 0L, 255L))
  expect_identical(px[1, 2, ], c(0L, 0L, 255L, 255L))
  expect_identical(px[1, 3, ], c(127L, 0L, 127L, 255L))  # composite: mean of a and b
  expect_identical(px[2, 2, 4], 0L)
  m[1, 3] <- 0L
  pc <- decode(.mask_data_uri(.new_annot_mask(m, lg, 0L, c(4L, 4L), "multiclass")))
  expect_identical(pc[1, 2, ], c(0L, 0L, 255L, 255L))
  expect_identical(pc[1, 3, 4], 0L)
})

# ---- JavaScript contract (static) -----------------------------------------
# Behaviour is covered by node --test tests/audit/widget.test.js and the
# browser lane below.

test_that("the widget registers one Shiny message handler per name (A25)", {
  js <- readLines(system.file("htmlwidgets", "atcanvas.js", package = "hyperannotatR"))
  expect_length(grep("addCustomMessageHandler(", js, fixed = TRUE), 1L)
  expect_true(any(grepl("instances[m.id]", js, fixed = TRUE)))
})

# ---- Real browser: JavaScript behaviour ------------------------------------
# Opt-in like the app journeys: ANNOTATR_BROWSER_TESTS=true and a Chrome that
# chromote can start (CHROMOTE_CHROME may name one). The page is a static
# widget with a recording stand-in for Shiny, so every event the canvas would
# send to R is observable. tests/browser/widget.cjs qualifies the widget with
# a real Shiny server.

browser_page <- function(dir) {
  skip_if_not(identical(Sys.getenv("ANNOTATR_BROWSER_TESTS"), "true"),
              "set ANNOTATR_BROWSER_TESTS=true to run the canvas browser tests")
  skip_if_not_installed("chromote")
  skip_if_not_installed("magick")
  skip_if(is.null(tryCatch(chromote::find_chrome(), error = function(e) NULL)), "no Chrome found")
  img <- pixel_image(nb = 3L, w = 100L, h = 100L)
  .reset_id_counter()
  donut <- at_roi_polygon(rbind(c(10, 10), c(90, 10), c(90, 90), c(10, 90)), label = "d")
  hole <- sf::st_polygon(list(rbind(c(10, 10), c(90, 10), c(90, 90), c(10, 90), c(10, 10)),
                              rbind(c(30, 30), c(70, 30), c(70, 70), c(30, 70), c(30, 30))))
  donut$geometry <- sf::st_sfc(hole, crs = sf::NA_crs_)
  lyr <- at_layer_add(at_layer("l", labels = "d"), donut)
  locked <- at_layer_add(at_layer("k", labels = "k", style = at_style(locked = TRUE)),
                         at_roi_rect(92, 92, 99, 99, label = "k"))
  proj <- at_project(img, list(lyr, locked))
  wa <- at_canvas(img, project = proj, tool = "erase", elementId = "a", width = 400, height = 400)
  wb <- at_canvas(img, tool = "pan", elementId = "b", width = 400, height = 400)
  wc <- at_canvas(img, elementId = "c", width = 200, height = 200)
  wc$x$tileSource$dataUri <- NULL
  wc$x$tileSource$displayError <- "Canvas display requires package magick."
  # Widget b's canvas gets its own border and padding: pointer positions must
  # still map exactly onto the drawn image (W20).
  css <- htmltools::tags$style("#b canvas { border: 3px solid #f00; padding: 2px; }")
  # A stand-in for Shiny that records inputs and handler registrations. It runs
  # before the widgets render (static mode, so htmlwidgets does not need it).
  fake <- htmltools::tags$script(htmltools::HTML(paste(
    "window.__ev = []; window.__h = {}; window.__hn = {};",
    "window.Shiny = { setInputValue: function (n, v) { window.__ev.push([n, JSON.parse(JSON.stringify(v))]); },",
    "  addCustomMessageHandler: function (n, f) { window.__h[n] = f; window.__hn[n] = (window.__hn[n] || 0) + 1; } };"
  )))
  page <- htmltools::tagList(fake, css, wa, wb, wc)
  f <- file.path(dir, "canvas.html")
  htmltools::save_html(page, f, libdir = file.path(dir, "lib"))
  b <- chromote::ChromoteSession$new(width = 1000, height = 1400)
  withr::defer(b$close(), envir = parent.frame())
  b$Page$navigate(paste0("file://", normalizePath(f)), wait_ = TRUE)
  ev <- function(js) b$Runtime$evaluate(js, returnByValue = TRUE, awaitPromise = TRUE)$result$value
  for (k in 1:50) {
    if (isTRUE(ev("!!(window.atcanvasInspect && window.atcanvasInspect('a') && window.atcanvasInspect('a').hasImage && window.atcanvasInspect('b').hasImage)"))) break
    Sys.sleep(0.1)
  }
  list(b = b, ev = ev)
}

inspect_js <- function(id, field) sprintf("window.atcanvasInspect('%s').%s", id, field)

# Trusted pointer input through the DevTools protocol (the real pointer path).
cdp_click <- function(pg, id, ix, iy, to = NULL) {
  p <- pg$ev(sprintf("window.atcanvasInspect('%s').toClient(%f, %f)", id, ix, iy))
  q <- if (is.null(to)) p else pg$ev(sprintf("window.atcanvasInspect('%s').toClient(%f, %f)", id, to[1], to[2]))
  pg$b$Input$dispatchMouseEvent(type = "mousePressed", x = p[[1]], y = p[[2]], button = "left", clickCount = 1)
  if (!is.null(to)) {
    for (t in seq(0.25, 1, by = 0.25)) {
      pg$b$Input$dispatchMouseEvent(type = "mouseMoved", x = p[[1]] + t * (q[[1]] - p[[1]]),
                                    y = p[[2]] + t * (q[[2]] - p[[2]]), button = "left", buttons = 1)
    }
  }
  pg$b$Input$dispatchMouseEvent(type = "mouseReleased", x = q[[1]], y = q[[2]], button = "left", clickCount = 1)
}
# Envelopes sent for input `name`; each is list(entry_id, revision, payload).
events <- function(pg, name) {
  ev <- pg$ev("window.__ev")
  lapply(Filter(function(e) identical(e[[1]], name), ev), `[[`, 2L)
}

test_that("canvas JS: holes, routing, edits, cancelling, provisional shapes, errors", {
  dir <- withr::local_tempdir()
  pg <- browser_page(dir)
  # One handler per message name, shared by all three widgets (A25).
  expect_true(all(unlist(pg$ev("Object.values(window.__hn)")) == 1L))
  expect_setequal(names(pg$ev("window.__hn")), paste0("atcanvas-", c(
    "set_annotations", "set_tool", "set_band", "set_overlay", "fit_bounds", "set_selection", "clear_overlay")))

  # A24: a click in the donut hole hits nothing; a click on the ring erases it.
  cdp_click(pg, "a", 50, 50)
  expect_length(events(pg, "a_erased"), 0L)
  cdp_click(pg, "a", 20, 50)
  er <- events(pg, "a_erased")
  expect_identical(er[[1]]$payload, "roi_000000001")
  expect_identical(er[[1]]$entry_id, "a")  # a standalone widget stamps its element id
  # A locked layer is not erased from the canvas.
  cdp_click(pg, "a", 95, 95)
  expect_length(events(pg, "a_erased"), 1L)
  expect_match(pg$ev(inspect_js("a", "status")), "locked")

  # A25: proxy messages for B leave A's tool alone, and vice versa.
  pg$ev("window.__h['atcanvas-set_tool']({id: 'b', tool: 'point'})")
  expect_identical(pg$ev(inspect_js("a", "tool")), "erase")
  expect_identical(pg$ev(inspect_js("b", "tool")), "point")
  cdp_click(pg, "b", 40, 40)
  pt <- events(pg, "b_created")
  expect_length(pt, 1L)
  expect_identical(pt[[1]]$payload$geometry$type, "Point")
  expect_lt(max(abs(unlist(pt[[1]]$payload$geometry$coordinates) - c(40, 40))), 0.3)

  # W24: an edit click without a drag sends nothing; a drag sends the move.
  pg$ev("window.__h['atcanvas-set_tool']({id: 'a', tool: 'edit'})")
  pg$ev("window.__h['atcanvas-set_annotations']({id: 'a', annotations: {type: 'FeatureCollection', features: [{type: 'Feature', geometry: {type: 'Polygon', coordinates: [[[10,10],[40,10],[40,40],[10,40],[10,10]]]}, properties: {roi_id: 'r1', layer: 'l', label: 'd'}}]}})")
  cdp_click(pg, "a", 20, 20)
  expect_length(events(pg, "a_edited"), 0L)
  cdp_click(pg, "a", 20, 20, to = c(30, 25))
  ed <- events(pg, "a_edited")
  expect_length(ed, 1L)
  ring <- matrix(unlist(ed[[1]]$payload$geometry$coordinates), ncol = 2, byrow = TRUE)
  expect_lt(max(abs(ring[1, ] - c(20, 15))), 0.3)
  expect_identical(pg$ev(inspect_js("a", "pendingEdits")), 1L)

  # W11: Escape cancels an unfinished polygon; a tool change discards it too.
  pg$ev("window.__h['atcanvas-set_tool']({id: 'b', tool: 'polygon'})")
  cdp_click(pg, "b", 10, 10)
  cdp_click(pg, "b", 60, 10)
  expect_identical(pg$ev(inspect_js("b", "vertices")), 2L)
  pg$b$Input$dispatchKeyEvent(type = "keyDown", key = "Escape", code = "Escape", windowsVirtualKeyCode = 27)
  expect_identical(pg$ev(inspect_js("b", "vertices")), 0L)
  cdp_click(pg, "b", 10, 10)
  pg$ev("window.__h['atcanvas-set_tool']({id: 'b', tool: 'freehand'})")
  expect_identical(pg$ev(inspect_js("b", "vertices")), 0L)
  pg$ev("window.__h['atcanvas-set_tool']({id: 'b', tool: 'polygon'})")
  for (v in list(c(10, 10), c(60, 10), c(60, 60))) cdp_click(pg, "b", v[1], v[2])
  cdp_click(pg, "b", 10.5, 10.5)  # clicking the first vertex closes the polygon
  poly <- events(pg, "b_created")
  expect_length(poly, 2L)
  ring <- matrix(unlist(poly[[2]]$payload$geometry$coordinates), ncol = 2, byrow = TRUE)
  expect_identical(nrow(ring), 4L)  # three vertices plus the closing one
  expect_equal(ring[1, ], ring[4, ])

  # W10: a click with the rect tool is not a rectangle, and an unconfirmed
  # shape is provisional until R answers.
  pg$ev("window.__h['atcanvas-set_tool']({id: 'b', tool: 'rect'})")
  cdp_click(pg, "b", 20, 20)
  expect_length(events(pg, "b_created"), 2L)
  cdp_click(pg, "b", 20, 20, to = c(50, 50))
  expect_length(events(pg, "b_created"), 3L)
  rect <- matrix(unlist(events(pg, "b_created")[[3]]$payload$geometry$coordinates), ncol = 2, byrow = TRUE)
  expect_lt(max(abs(apply(rect, 2, range) - rbind(c(20, 20), c(50, 50)))), 0.3)
  db <- pg$ev("(function(){var i=window.atcanvasInspect('b'); return [i.backingW, i.viewW];})()")
  expect_equal(db[[1]] / db[[2]], pg$ev("window.devicePixelRatio"), tolerance = 0.01)
  expect_gte(pg$ev(inspect_js("b", "pending")), 1L)
  pg$ev("window.__h['atcanvas-set_annotations']({id: 'b', annotations: {type: 'FeatureCollection', features: []}})")
  expect_identical(pg$ev(inspect_js("b", "pending")), 0L)

  # The synthetic-mouse fallback still drives the canvas (used by app tests).
  pg$ev("(function(){var c=document.querySelector('#b canvas');var r=c.getBoundingClientRect();
    function e(t,fx,fy){c.dispatchEvent(new MouseEvent(t,{bubbles:true,clientX:r.left+fx*r.width,clientY:r.top+fy*r.height}));}
    e('mousedown',0.3,0.3);e('mousemove',0.6,0.6);e('mouseup',0.6,0.6);})()")
  expect_length(events(pg, "b_created"), 4L)
  # Without an answer from R the provisional shape disappears.
  expect_identical(pg$ev(inspect_js("b", "pending")), 1L)
  Sys.sleep(5.5)
  expect_identical(pg$ev(inspect_js("b", "pending")), 0L)

  # W3: a missing image shows the reason instead of a stale picture.
  expect_false(pg$ev(inspect_js("c", "hasImage")))
  expect_match(pg$ev(inspect_js("c", "status")), "requires package magick")
  # An image load that finishes after a newer render must not resurrect the
  # old image (here the newer render has no image at all).
  pg$ev(sprintf("(function(){var w=HTMLWidgets.find('#c');
    w.renderValue({tileSource:{width:100,height:100,dataUri:'%s'},annotations:{features:[]},tool:'pan'});
    w.renderValue({tileSource:{width:100,height:100,displayError:'decoder failed'},annotations:{features:[]},tool:'pan'});})()",
    .image_data_uri(pixel_image(nb = 3L, w = 100L, h = 100L))))
  Sys.sleep(0.5)
  expect_false(pg$ev(inspect_js("c", "hasImage")))
  expect_match(pg$ev(inspect_js("c", "status")), "decoder failed")

  # W20: touch input draws, and two fingers pinch-zoom.
  pg$ev("window.__h['atcanvas-set_tool']({id: 'b', tool: 'rect'})")
  n0 <- length(events(pg, "b_created"))
  p1 <- pg$ev("window.atcanvasInspect('b').toClient(20, 20)")
  p2 <- pg$ev("window.atcanvasInspect('b').toClient(60, 50)")
  pg$b$Input$dispatchTouchEvent(type = "touchStart", touchPoints = list(list(x = p1[[1]], y = p1[[2]])))
  pg$b$Input$dispatchTouchEvent(type = "touchMove", touchPoints = list(list(x = p2[[1]], y = p2[[2]])))
  pg$b$Input$dispatchTouchEvent(type = "touchEnd", touchPoints = list())
  tr <- events(pg, "b_created")
  expect_length(tr, n0 + 1L)
  rect <- matrix(unlist(tr[[n0 + 1L]]$payload$geometry$coordinates), ncol = 2, byrow = TRUE)
  expect_lt(max(abs(apply(rect, 2, range) - rbind(c(20, 20), c(60, 50)))), 0.3)
  pg$ev("window.__h['atcanvas-set_tool']({id: 'b', tool: 'pan'})")
  zb <- pg$ev(inspect_js("b", "zoom"))
  c0 <- pg$ev("window.atcanvasInspect('b').toClient(50, 50)")
  pg$b$Input$dispatchTouchEvent(type = "touchStart", touchPoints = list(
    list(x = c0[[1]] - 20, y = c0[[2]], id = 1), list(x = c0[[1]] + 20, y = c0[[2]], id = 2)))
  pg$b$Input$dispatchTouchEvent(type = "touchMove", touchPoints = list(
    list(x = c0[[1]] - 60, y = c0[[2]], id = 1), list(x = c0[[1]] + 60, y = c0[[2]], id = 2)))
  pg$b$Input$dispatchTouchEvent(type = "touchEnd", touchPoints = list())
  expect_gt(pg$ev(inspect_js("b", "zoom")), zb * 2)
  expect_length(events(pg, "b_created"), n0 + 1L)  # a pinch draws nothing

  # W20: zoom stays within limits.
  z0 <- pg$ev(inspect_js("a", "zoom"))
  p <- pg$ev("window.atcanvasInspect('a').toClient(50, 50)")
  for (k in 1:60) pg$b$Input$dispatchMouseEvent(type = "mouseWheel", x = p[[1]], y = p[[2]], deltaX = 0, deltaY = -100)
  expect_lte(pg$ev(inspect_js("a", "zoom")), max(z0 * 4, 32) + 1e-6)
})

test_that("the canvas shows an 8-bit image with its stored values and stretches deeper data", {
  skip_if_not_installed("magick")
  tissue <- at_example_image("tissue")
  arr <- .view_display_array(tissue, NULL)
  expect_equal(arr[200, 180, ], c(192, 95, 167) / 255)
  skip_if_not_installed("tiff")
  multiplex <- at_read_image(at_example_path("multiplex"))
  expect_false(identical(multiplex$dtype, "uint8"))
  stretched <- .view_display_array(multiplex, NULL)
  expect_equal(range(stretched), c(0, 1))
})

test_that("canvas script URLs change with content for both Shiny and standalone widgets", {
  skip_if_not_installed("magick")
  path <- tempfile(fileext = ".js")
  writeLines("// first build", path)
  first <- .canvas_asset_version("0.3.0", path)
  expect_identical(.canvas_asset_version("0.3.0", path), first)
  writeLines("// patched build", path)
  second <- .canvas_asset_version("0.3.0", path)
  expect_false(identical(first, second))
  expect_gt(package_version(first), package_version("0.3.0"))
  binding <- function(deps) {
    Filter(function(d) d$name == "atcanvas-binding",
           htmltools::resolveDependencies(deps))[[1]]
  }
  expected <- .canvas_asset_version(as.character(utils::packageVersion("hyperannotatR")),
    system.file("htmlwidgets", "atcanvas.js", package = "hyperannotatR"))
  expect_identical(binding(htmltools::htmlDependencies(atCanvasOutput("x")))$version,
                   expected)
  widget <- at_canvas(at_example_image("tissue"))
  html <- htmltools::as.tags(widget)
  expect_identical(binding(htmltools::findDependencies(html))$version, expected)
})
