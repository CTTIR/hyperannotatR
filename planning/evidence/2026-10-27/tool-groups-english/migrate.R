args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
root <- args[1]; out <- args[2]; report <- args[3]
work <- '$TMPDIR/tool-groups'
.libPaths(c(file.path(root, 'library'), .libPaths()))
suppressPackageStartupMessages(library(hyperannotatR))
source(file.path(work, 'names.R'), encoding = 'UTF-8')
before <- at_resume(file.path(root, 'annotations/_session.rds'))
after <- before
stopifnot(identical(vapply(before$layer_spec, `[[`, '', 'name'), names(layer_names)),
          all(before$labels %in% names(label_names)))
after$layer_spec <- lapply(after$layer_spec, rename_layer)
source(file.path(work, 'layers.R'), encoding = 'UTF-8')
stopifnot(identical(after$layer_spec, tsci_layers()))
after$labels <- translate(after$labels, label_names)
if (!is.null(names(after$layer_spec)))
  names(after$layer_spec) <- translate(names(after$layer_spec), layer_names)
original <- list()
for (i in seq_along(after$projects)) {
  p <- after$projects[[i]]
  path <- after$manifest$project_path[i]
  if (is.null(p) && !is.na(path) && nzchar(path)) p <- at_load_project(path)
  if (is.null(p)) next
  original[[as.character(i)]] <- p
  stopifnot(all(names(p$layers) %in% names(layer_names)))
  p$layers <- lapply(p$layers, rename_layer)
  names(p$layers) <- translate(names(p$layers), layer_names)
  after$projects[[i]] <- p
}
after$meta$calibration_reference$layer <- 'Calibration'
after$meta$calibration_reference$label <- 'Retractor thickness'
after$meta$nomenclature <- list(language = 'English', case = 'sentence',
  layers = as.list(layer_names), labels = as.list(label_names),
  updated_utc = format(Sys.time(), tz = 'UTC', usetz = TRUE))
after$out_dir <- out
dir.create(out, recursive = TRUE, showWarnings = FALSE)
after <- hyperannotatR:::.save_checkpoint(after, after$cursor)
loaded <- at_resume(file.path(out, '_session.rds'))
for (field in c('entry_id', 'n_rois', 'path', 'status'))
  stopifnot(identical(loaded$manifest[[field]], before$manifest[[field]]))
stopifnot(identical(loaded$cursor, before$cursor))
checked_rois <- 0L
for (key in names(original)) {
  p <- at_current(at_goto(loaded, as.integer(key)))
  old <- original[[key]]
  for (name in names(old$layers)) {
    current <- p$layers[[unname(layer_names[name])]]
    expected <- rename_layer(old$layers[[name]])
    stopifnot(identical(current, expected))
    for (j in seq_along(current$rois)) {
      # Explicitly undo the name change and compare every ROI field,
      # including exact geometry, identity, attributes and timestamps.
      roi <- current$rois[[j]]
      roi$label <- old$layers[[name]]$rois[[j]]$label
      stopifnot(identical(roi, old$layers[[name]]$rois[[j]]))
      checked_rois <- checked_rois + 1L
    }
  }
  stopifnot(identical(p$image$pixel_size, old$image$pixel_size),
            identical(p$image$pixel_unit, old$image$pixel_unit))
  summary <- get('.calibration_summary', asNamespace('hyperannotatR'))
  stopifnot(identical(summary(old, 'Kalibrierung', 'Retraktorstärke'),
                      summary(p, 'Calibration', 'Retractor thickness')))
}
for (i in seq_len(nrow(loaded$manifest))) {
  p <- at_current(at_goto(loaded, i))
  stopifnot(identical(names(p$layers), unname(layer_names)),
            all(unlist(lapply(p$layers, `[[`, 'labels')) %in% unname(label_names)))
}
stopifnot(checked_rois == sum(before$manifest$n_rois))
result <- list(status = 'pass', images_checked = nrow(loaded$manifest),
  roi_fields_preserved_except_label = TRUE, checked_rois = checked_rois,
  completion_statuses_identical = TRUE, physical_scale_unchanged = TRUE,
  calibration_statistics_identical = TRUE,
  completed_images = sum(loaded$manifest$status == 'complete'),
  cursor = loaded$cursor, layers = as.list(layer_names),
  labels = as.list(label_names), checkpoint = file.path(out, '_session.rds'))
jsonlite::write_json(result, report, auto_unbox = TRUE, pretty = TRUE)
cat('PASS: English names on all', nrow(loaded$manifest), 'images;', checked_rois,
    'ROIs retain every field except label text; completion and scale preserved.\n')
