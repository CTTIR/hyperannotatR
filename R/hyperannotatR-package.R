#' @keywords internal
"_PACKAGE"

# sf is imported, not only called with `::`, so that loading hyperannotatR loads sf
# and registers its S3 methods: without them c() and `[` on the geometries of
# a project read from disk fall back to the base list methods (A34).
#' @importFrom rlang .data %||% caller_env caller_arg
#' @importFrom sf st_sfc
#' @importFrom stats median sd
NULL
