layer_names <- c(
  'Whole spinal cord' = 'Whole spinal cord',
  'Visually injured cord' = 'Visually injured spinal cord',
  'Artifacts' = 'Artifacts',
  'Optimal spinal cord reference' = 'Optimal spinal cord view',
  'Kalibrierung' = 'Calibration')
label_names <- c(
  'whole_cord' = 'Whole spinal cord',
  'visually_injured' = 'Visually injured spinal cord',
  'blood_overlay' = 'Blood overlay',
  'other_artifact' = 'Other artifact',
  'reflectations' = 'Reflections',
  'optimal_reference' = 'Optimal spinal cord view',
  'Retraktorstärke' = 'Retractor thickness')
translate <- function(x, map) {
  hit <- match(x, names(map))
  x[!is.na(hit)] <- unname(map[hit[!is.na(hit)]])
  x
}
rename_layer <- function(layer) {
  layer$name <- translate(layer$name, layer_names)
  layer$labels <- translate(layer$labels, label_names)
  for (field in c('colour', 'colour_spec')) {
    if (!is.null(names(layer$style[[field]])))
      names(layer$style[[field]]) <- translate(names(layer$style[[field]]), label_names)
  }
  layer$rois <- lapply(layer$rois, function(roi) {
    roi$label <- translate(roi$label, label_names)
    roi
  })
  if (identical(layer$meta$role, 'calibration_reference')) {
    layer$meta$definition <- 'Visible retractor thickness at a straight section with clear opposite edges'
    layer$meta$selection <- 'Measure across the same reference dimension with Distance at least 3 times, preferably 5; confirm the physical thickness separately'
  }
  layer
}
