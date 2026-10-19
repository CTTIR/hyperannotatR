skip_if_not_installed("magick")

test_that("the project manifest describes identity, convention and annotations without local paths", {
  proj <- at_example_project()
  m <- at_interop_manifest(proj)
  expect_s3_class(m, "at_interop_manifest")
  expect_identical(m$schema, "annotatr-handoff-v1")
  expect_identical(m$object_kind, "project")
  expect_identical(m$coordinate_convention$origin, "top_left")
  expect_identical(m$coordinate_convention$y_axis, "down")
  img <- m$images[[1]]
  # Independent image id: sha256 over the canonical {"files":["<file sha256>"]}.
  file_sha <- unname(tools::sha256sum(at_example_path("tissue")))
  expected <- substr(.sha256_bytes(sprintf('{"files":["%s"]}', file_sha)), 1, 16)
  expect_identical(img$image_id, paste0("sha256:", expected))
  expect_identical(img$source_name, "example_tissue.png")
  expect_identical(c(img$width, img$height), c(512L, 512L))
  expect_identical(m$annotations$count, 3L)
  ids <- vapply(m$annotations$rois, `[[`, character(1), "roi_id")
  expect_identical(ids, at_rois(proj)$roi_id)
  txt <- jsonlite::toJSON(unclass(m), auto_unbox = TRUE, null = "null", na = "null")
  expect_false(grepl(dirname(at_example_path("tissue")), txt, fixed = TRUE))
  expect_false(grepl(tempdir(), txt, fixed = TRUE))
  expect_length(.schema_validate(.as_json_value(unclass(m)),
                                 .schema_load("annotatr-handoff-v1", "manifest")), 0L)
})

test_that("the annotation revision follows content, not timestamps", {
  proj <- at_example_project()
  r0 <- at_annotation_revision(proj)
  expect_match(r0, "^sha256:[0-9a-f]{64}$")
  touched <- proj
  touched$layers$regions$rois[[1]]$modified <- Sys.time() + 3600
  touched$provenance$modified <- Sys.time() + 3600
  expect_identical(at_annotation_revision(touched), r0)
  moved <- proj
  moved$layers$regions$rois[[1]]$geometry <- sf::st_sfc(sf::st_polygon(list(rbind(
    c(0, 0), c(5, 0), c(5, 5), c(0, 5), c(0, 0)))))
  expect_false(identical(at_annotation_revision(moved), r0))
  relabelled <- proj
  relabelled$layers$regions$rois[[1]]$label <- "stroma"
  expect_false(identical(at_annotation_revision(relabelled), r0))
  locked <- proj
  locked$layers$regions$style$locked <- TRUE
  expect_false(identical(at_annotation_revision(locked), r0))
})

test_that("circles are declared approximated and hierarchy unknown", {
  proj <- at_add_roi(at_example_project(), "regions", at_roi_circle(40, 40, 10, label = "stroma"))
  rois <- at_interop_manifest(proj)$annotations$rois
  fid <- vapply(rois, `[[`, character(1), "geometry_fidelity")
  expect_identical(fid, c("exact", "exact", "exact", "approximated"))
  expect_true(all(vapply(rois, `[[`, character(1), "hierarchy") == "unknown"))
})

test_that("session, image, layer, ROI and mask manifests are schema-valid", {
  sess <- at_example_session(2)
  sess$projects[[2]] <- at_example_project()
  ms <- at_interop_manifest(sess)
  expect_identical(ms$object_kind, "session")
  q <- ms$session$queue
  expect_identical(vapply(q, `[[`, character(1), "entry_id"),
                   c(.session_entry_id(sess, 1), .session_entry_id(sess, 2)))
  expect_identical(vapply(q, `[[`, logical(1), "materialised"), c(FALSE, TRUE))
  schema <- .schema_load("annotatr-handoff-v1", "manifest")
  for (obj in list(sess, at_example_image("cube"), at_example_project()$layers$regions,
                   at_roi_rect(0, 0, 2, 2, label = "a"), at_mask(at_example_project(), "labelled"))) {
    man <- at_interop_manifest(obj, hash_sources = FALSE)
    expect_length(.schema_validate(.as_json_value(unclass(man)), schema), 0L)
  }
  cube <- at_interop_manifest(at_example_image("cube"))$images[[1]]
  expect_identical(cube$image_kind, "spectral")
  expect_identical(length(cube$bands), 40L)
  expect_equal(cube$bands[[1]]$wavelength, 450)
  expect_identical(vapply(cube$source_files, `[[`, character(1), "role"), c("header", "data"))
})

test_that("writing a manifest never overwrites", {
  d <- withr::local_tempdir()
  at_interop_manifest(at_example_project(), d)
  expect_true(file.exists(file.path(d, "manifest.json")))
  err <- tryCatch(at_interop_manifest(at_example_project(), d), error = function(e) e)
  expect_s3_class(err, "at_io_error")
  expect_identical(err$code, "DESTINATION_EXISTS")
  expect_error(at_interop_manifest(42), class = "at_validation_error")
})

test_that("dates, durations, raw and complex attributes do not break digests (X7)", {
  base <- at_example_project()
  add <- function(...) at_add_roi(base, "regions", at_roi_rect(1, 1, 5, 5, label = "tumour", ...))
  for (p in list(add(scanned = as.Date("2026-01-01")),
                 add(exposure = as.difftime(3, units = "secs")),
                 add(seen = as.POSIXct(c("2026-01-01 10:00:00", "2026-01-02 11:00:00"), tz = "UTC")),
                 add(blob = as.raw(c(1, 255))),
                 add(z = complex(real = 1, imaginary = 2)))) {
    expect_match(at_annotation_revision(p), "^sha256:[0-9a-f]{64}$")
    expect_s3_class(at_interop_manifest(p, hash_sources = FALSE), "at_interop_manifest")
  }
  expect_identical(.json_safe(as.Date("2026-01-01")), "2026-01-01")
  expect_identical(.json_safe(as.raw(c(1, 255))), "01ff")
  expect_identical(.json_safe(as.POSIXct(c("2026-01-01 10:00:00", NA), tz = "UTC")),
                   list("2026-01-01T10:00:00Z", NA_character_))
})

test_that("an unknown review status is refused with a clear code (X7)", {
  p <- at_add_roi(at_example_project(), "regions",
                  at_roi_rect(1, 1, 5, 5, label = "tumour", id = "odd", review_status = "approved"))
  err <- tryCatch(at_interop_manifest(p), error = function(e) e)
  expect_identical(err$code, "REVIEW_STATUS_INVALID")
  expect_match(conditionMessage(err), "odd")
})

test_that("session manifests key ROIs and layers by queue entry (X4)", {
  sess <- at_example_session(2)
  sess$projects[[1]] <- at_example_project()
  sess$projects[[2]] <- at_example_project()
  m <- at_interop_manifest(sess, hash_sources = FALSE)
  eids <- c(.session_entry_id(sess, 1), .session_entry_id(sess, 2))
  entries <- vapply(m$annotations$rois, `[[`, character(1), "entry_id")
  expect_identical(unique(entries), eids)
  expect_identical(vapply(m$layers, `[[`, character(1), "entry_id"), eids)
  expect_identical(vapply(m$session$queue, `[[`, character(1), "entry_id"), eids)
  expect_identical(vapply(m$session$queue, `[[`, integer(1), "queue_index"), 1:2)
  # Project manifests keep their layer records (and revisions) unchanged.
  expect_null(at_interop_manifest(at_example_project())$layers[[1]]$entry_id)
})

test_that("the image id distinguishes series, planes and measurements of one file (X4)", {
  img <- at_example_project()$image
  files <- .source_files(img)
  base <- .image_id(img, files)
  s1 <- img
  s1$meta$series_id <- 1L
  z1 <- img
  z1$meta$plane <- list(c = NA_integer_, z = 1L, t = 0L)
  m2 <- img
  m2$meta$measurement_index <- 2L
  ids <- c(base, .image_id(s1, files), .image_id(z1, files), .image_id(m2, files))
  expect_false(anyDuplicated(ids) > 0L)
  # Reader options that only change interpretation keep the content id.
  r <- img
  r$reader <- list(backend = "raster", args = list(value_unit = "reflectance"))
  expect_identical(.image_id(r, files), base)
})

test_that("stable session entry ids are used when present, positional ids otherwise (X4)", {
  sess <- at_example_session(2)
  sess$manifest$entry_id <- c("entry_ns_000000007", "bad id/../x")
  expect_identical(.session_entry_id(sess, 1), "entry_ns_000000007")
  expect_identical(.session_entry_id(sess, 2), "entry-0002")
  sess$manifest$entry_id <- NULL
  sess$projects[[1]] <- at_example_project()
  sess$projects[[1]]$meta$entry_id <- "entry_ns_000000003"
  expect_identical(.session_entry_id(sess, 1), "entry_ns_000000003")
  expect_identical(.session_entry_id(sess, 2), "entry-0002")
})

test_that("partner keys are looked up exactly, never by prefix (A33)", {
  r <- at_roi_rect(1, 1, 5, 5, label = "a")
  r$attributes <- list(review_status_note = "approved by X", locked_by = "someone",
                       shape_hint = "circle", plane_note = "z1")
  rec <- .roi_record(r, "l")
  expect_identical(rec$review_status, "unreviewed")
  expect_false(rec$locked)
  expect_identical(rec$geometry_fidelity, "exact")
  expect_identical(rec$plane, list(c = NA_integer_, z = 0L, t = 0L))
  expect_null(.jget(list(levels = 2L), "level"))
  expect_identical(.jget(list(a = list(b = 1L)), "a", "b"), 1L)
  expect_null(.jget(list(a = "x"), "a", "b"))
})
