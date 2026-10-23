# Isolated browser qualification of marker sizes and reflection proposals.
# Run from the package root with CHROMOTE_CHROME set to a Chromium executable.
work <- Sys.getenv('ANNOTATR_BROWSER_ARTIFACT_DIR', tempfile('drawing-tools-'))
dir.create(work, recursive = TRUE, showWarnings = FALSE)
repo <- normalizePath('.')
pkgload::load_all(repo, quiet = TRUE)
dir <- tempfile('browser-app-', tmpdir = work)
dir.create(dir, showWarnings = FALSE)
rgb <- array(0.2, c(60, 80, 3))
rgb[15:18, 30:34, ] <- 0.98
png::writePNG(rgb, file.path(dir, 'fixture.png'))
s <- at_session(file.path(dir, 'fixture.png'),
  layers = list(at_layer('Artifacts', labels = c('reflectations', 'blood_overlay'))),
  out_dir = file.path(dir, 'saved'), autosave = TRUE)
saveRDS(s, file.path(dir, 'session.rds'))
writeLines(c(
  sprintf('pkgload::load_all(%s, quiet=TRUE)', deparse(repo)),
  sprintf('hyperannotatR::at_app(session=readRDS(%s))',
    deparse(file.path(dir, 'session.rds')))), file.path(dir, 'app.R'))
app <- shinytest2::AppDriver$new(dir, name = 'drawing-controls',
  load_timeout = 90000, timeout = 30000, width = 1500, height = 1100)
tryCatch({
  ready <- function() {
    app$wait_for_idle()
    app$wait_for_js("window.atcanvasInspect && window.atcanvasInspect('canvas-canvas') && window.atcanvasInspect('canvas-canvas').ready")
  }
  click <- function(id) app$run_js(sprintf("document.getElementById('%s').click()", id))
  tool <- function(name) {
    click(paste0('canvas-tool_', name))
    app$wait_for_js(sprintf("window.atcanvasInspect('canvas-canvas').tool === '%s'", name))
  }
  at <- function(x, y) {
    app$run_js(sprintf("(function(){var p=window.atcanvasInspect('canvas-canvas').toClient(%f,%f);var c=document.querySelector('#canvas-canvas canvas');c.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,clientX:p[0],clientY:p[1]}));c.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,clientX:p[0],clientY:p[1]}));})()", x, y))
  }
  ready()
  tool('point')
  app$wait_for_js("document.getElementById('canvas-point_radius').closest('.shiny-input-container').offsetParent !== null")
  app$set_inputs(`canvas-point_radius` = '8')
  ready(); at(10, 10)
  app$wait_for_value(export = 'n_rois', ignore = list(0L))
  stopifnot(app$get_value(export = 'n_rois') == 1L)
  tool('circle')
  app$wait_for_js("document.getElementById('canvas-circle_radius').closest('.shiny-input-container').offsetParent !== null")
  for (i in 1:3) {
    app$set_inputs(`canvas-circle_radius` = c('2.5','5','10')[i])
    ready(); at(15 + i * 15, 40)
    app$wait_for_value(export = 'n_rois', ignore = list(as.integer(i)))
    stopifnot(app$get_value(export = 'n_rois') == i + 1L)
  }
  tool('reflection')
  ready(); at(31,16)
  app$wait_for_js("document.getElementById('canvas-accept_reflection') !== null")
  stopifnot(app$get_value(export = 'n_rois') == 4L)
  click('canvas-discard_reflection')
  app$wait_for_js("document.getElementById('canvas-accept_reflection') === null")
  ready(); at(31,16)
  app$wait_for_js("document.getElementById('canvas-accept_reflection') !== null")
  app$get_screenshot(file = file.path(work, paste0(basename(dir), '-reflection-preview.png')))
  click('canvas-accept_reflection')
  app$wait_for_value(export = 'n_rois', ignore = list(4L))
  stopifnot(app$get_value(export = 'n_rois') == 5L)
  ready()
  saved <- at_resume(file.path(dir, 'saved/_session.rds'))
  rois <- saved$projects[[1]]$layers$Artifacts$rois
  stopifnot(length(rois) == 5L, rois[[1]]$attributes$point_radius == 8,
    all(vapply(rois[2:4], function(r) as.numeric(sf::st_area(r$geometry)), 0) > 0),
    as.numeric(sf::st_area(rois[[5]]$geometry)) == 20,
    isTRUE(rois[[5]]$attributes$reviewed))
  for (i in 1:3) {
    bbox <- sf::st_bbox(rois[[i+1]]$geometry)
    stopifnot(abs(unname(bbox['xmax'] - bbox['xmin']) - c(5,10,20)[i]) < 1e-8)
  }
  cat('PASS: visible size selectors, three fixed diameters, point size persistence,\n')
  cat('reflection preview/discard/accept and exact saved 20-pixel geometry.\n')
}, finally = app$stop())
