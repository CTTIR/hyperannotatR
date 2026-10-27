# Visible tool names and groups are separate from the stable event/tool IDs.
.canvas_toolbar_ui <- function(id) {
  ns <- shiny::NS(id)
  button <- function(action, label, icon, hint) {
    .at_action(ns(action), shiny::span(class = "at-tool-label", label),
      icon = htmltools::tagAppendAttributes(shiny::icon(icon),
                                            `aria-hidden` = "true"),
      class = "at-tool-button", title = hint, `aria-label` = label,
      `aria-pressed` = if (startsWith(action, "tool_")) "false" else NULL)
  }
  group <- function(key, label, ...) {
    shiny::div(class = "at-tool-group", role = "group",
      `aria-labelledby` = ns(paste0("tools_", key)),
      shiny::span(id = ns(paste0("tools_", key)),
                  class = "at-tool-group-label", label),
      shiny::div(class = "at-tool-actions", ...))
  }
  shiny::div(class = "at-tool-palette", role = "group",
    `aria-label` = "Annotation tools",
    group("navigate", "Navigate",
      button("tool_pan", "Pan", "hand", "Drag to move the image (Q)."),
      button("tool_select", "Select", "arrow-pointer",
             "Click a region to select it."),
      button("tool_probe", "Inspect spectrum", "chart-line",
             "Click an image pixel to inspect its spectrum.")),
    group("draw", "Draw & mark",
      button("tool_polygon", "Polygon", "draw-polygon",
             "Click vertices, then close the region (E)."),
      button("tool_freehand", "Freehand", "pencil",
             "Draw a region by dragging its outline (R)."),
      button("tool_rect", "Rectangle", "vector-square",
             "Drag between opposite corners (W)."),
      button("tool_circle", "Round area", "circle",
             "Place a round area using the selected diameter (T)."),
      button("tool_point", "Point", "location-dot",
             "Mark one image pixel; marker size is display only (Y).")),
    group("measure", "Measure & detect",
      button("tool_line", "Distance", "ruler",
             "Click the start and end of a straight reference length."),
      button("tool_reflection", "Reflection wand", "wand-magic-sparkles",
             "Click a bright reflection, then review the proposed region.")),
    group("edit", "Edit & reuse",
      button("tool_edit", "Move region", "arrows-up-down-left-right",
             "Drag an existing region to move it."),
      button("tool_erase", "Erase region", "eraser",
             "Click an existing region to remove it."),
      button("undo", "Undo", "rotate-left",
             "Undo the last annotation change (Ctrl/Cmd+Z)."),
      button("redo", "Redo", "rotate-right",
             "Redo the last undone change (Ctrl/Cmd+Shift+Z)."),
      button("copy", "Copy previous", "copy",
             "Copy regions from the previous image (Shift+V). Calibration references are not copied.")))
}
