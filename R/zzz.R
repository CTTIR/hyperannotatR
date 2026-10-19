# Package hooks.

# What a built-in reader actually does, as reported by at_backend_list():
# whether opening reads only metadata, whether tiles are read as windows, the
# sample semantics, and the I/O style.
.backend_capabilities <- function(metadata_only, window_read, samples, io) {
  list(metadata_only = metadata_only, window_read = window_read, samples = samples, io = io)
}

.register_backends <- function() {
  at_backend_register(
    "raster", .raster_read, .raster_tile, .raster_detect, .raster_available,
    description = "PNG, JPEG, and single-plane TIFF (display conversion to 0-255; not raw high-bit-depth samples)",
    capabilities = .backend_capabilities(FALSE, FALSE, "display-converted-0-255", "eager"),
    extensions = c("png", "jpg", "jpeg", "bmp", "gif", "tif", "tiff")
  )
  at_backend_register(
    "tiff", .tiff_read, .tiff_tile, .tiff_detect, .tiff_available,
    description = "Pyramidal / multi-directory TIFF",
    capabilities = .backend_capabilities(FALSE, FALSE, "raw-scalar-v1", "eager"),
    extensions = c("tif", "tiff")
  )
  at_backend_register(
    "ometiff", .ometiff_read, .ometiff_tile, .ometiff_detect, .ometiff_available,
    description = "OME-TIFF and qptiff (RBioFormats)",
    capabilities = .backend_capabilities(FALSE, FALSE, "unqualified", "eager"),
    extensions = c("ome.tif", "ome.tiff", "qptiff")
  )
  at_backend_register(
    "cuvis", .cuvis_read, .cuvis_tile, .cuvis_detect, .cuvis_available,
    description = "Cubert hyperspectral (cuvis.r)",
    capabilities = .backend_capabilities(FALSE, FALSE, "unqualified", "eager"),
    extensions = c("cu3", "cu3s")
  )
  at_backend_register(
    "tivita", .tivita_read, .tivita_tile, .tivita_detect, .tivita_available,
    description = "Diaspective Vision Tivita (ENVI-compatible)",
    capabilities = .backend_capabilities(TRUE, TRUE, "raw-scalar-v1", "binary"),
    extensions = c("dat", "hdr")
  )
  at_backend_register(
    "envi", .envi_read, .envi_tile, .envi_detect, .envi_available,
    description = "ENVI header + binary cube",
    capabilities = .backend_capabilities(TRUE, TRUE, "raw-scalar-v1", "binary"),
    extensions = c("hdr", "dat", "img", "raw")
  )
  invisible(NULL)
}

.onLoad <- function(libname, pkgname) {
  .initialize_identity_state()
  .register_backends()
}
