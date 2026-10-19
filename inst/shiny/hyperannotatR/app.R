# Compatibility entry point for shiny::runApp() on this directory. All app code
# lives in the hyperannotatR package; the app object comes from hyperannotatR::at_app().
# An annot_session may be passed through the legacy option `hyperannotatR.session`,
# which is read here only for this compatibility path.
hyperannotatR::at_app(session = getOption("hyperannotatR.session", default = NULL))
