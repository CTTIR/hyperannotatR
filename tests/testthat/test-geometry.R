test_that("set operations produce geometrically correct areas", {
  a <- at_roi_rect(0, 0, 6, 6, label = "x")
  b <- at_roi_rect(4, 4, 10, 10, label = "x")
  expect_equal(at_roi_area(at_roi_union(a, b)), 68)
  expect_equal(at_roi_area(at_roi_intersect(a, b)), 4)
  expect_equal(at_roi_area(at_roi_difference(a, b)), 32)
  expect_equal(at_roi_area(at_roi_symdiff(a, b)), 64)
})

test_that("set operations return a single derived annot_roi", {
  a <- at_roi_rect(0, 0, 6, 6, label = "x")
  b <- at_roi_rect(4, 4, 10, 10, label = "x")
  u <- at_roi_union(a, b)
  expect_s3_class(u, "annot_roi")
  expect_identical(u$source, "derived")
})

test_that("set operations accept a single layer", {
  pair <- overlap_pair()
  lyr <- at_layer_add(at_layer_add(at_layer("l"), pair$a), pair$b)
  expect_s3_class(at_roi_union(lyr), "annot_roi")
})

test_that("at_transform is exactly invertible across pyramid levels", {
  img <- small_image()
  r <- at_roi_rect(0, 0, 80, 80, label = "a")
  for (lv in c(1L, 2L)) {
    back <- at_transform(at_transform(r, 0, lv, img), lv, 0, img)
    expect_equal(sf::st_coordinates(r$geometry),
                 sf::st_coordinates(back$geometry), tolerance = 1e-9)
  }
})

test_that("at_transform uses real level dimensions", {
  img <- small_image() # levels 100, 50, 25
  r <- at_roi_point(80, 40, label = "a")
  r2 <- at_transform(r, 0, 1, img)
  expect_equal(as.numeric(sf::st_coordinates(r2$geometry))[1:2], c(40, 20))
})

test_that("flip_y is self-inverse", {
  r <- at_roi_rect(0, 0, 10, 5, label = "a")
  back <- at_flip_y(at_flip_y(r, 100), 100)
  expect_equal(sf::st_coordinates(r$geometry),
               sf::st_coordinates(back$geometry), tolerance = 1e-9)
})

test_that("snap rounds vertices to the grid", {
  r <- at_snap(at_roi_point(3.4, 5.6, label = "a"), grid = 1)
  expect_equal(as.numeric(sf::st_coordinates(r$geometry))[1:2], c(3, 6))
})

test_that("clamp clips to image bounds", {
  r <- at_clamp(at_roi_rect(-5, -5, 20, 20, label = "a"), dims = c(10, 10))
  expect_equal(at_roi_area(r), 100)
})

test_that("at_roi_contains vectorises over points", {
  r <- at_roi_rect(0, 0, 10, 10, label = "a")
  expect_identical(at_roi_contains(r, c(5, 20), c(5, 20)), c(TRUE, FALSE))
  expect_identical(at_roi_contains(r, numeric(0), numeric(0)), logical(0))
})

test_that("at_roi_overlaps and at_roi_distance are correct", {
  a <- at_roi_rect(0, 0, 6, 6, label = "a")
  b <- at_roi_rect(4, 4, 10, 10, label = "a")
  c <- at_roi_rect(20, 20, 25, 25, label = "a")
  expect_true(at_roi_overlaps(a, b))
  expect_false(at_roi_overlaps(a, c))
  expect_equal(at_roi_distance(at_roi_rect(0, 0, 1, 1, label = "a"),
                               at_roi_rect(5, 0, 6, 1, label = "a")), 4)
})

test_that("at_rois_overlap reports overlapping pairs, empty-safe", {
  pair <- overlap_pair()
  lyr <- at_layer_add(at_layer_add(at_layer("l"), pair$a), pair$b)
  ov <- at_rois_overlap(lyr)
  expect_equal(nrow(ov), 1L)
  expect_identical(names(ov), c("id_a", "id_b", "overlap_px", "jaccard"))
  expect_equal(ov$overlap_px, 4)
  # No overlaps -> 0 rows, same columns.
  lyr2 <- at_layer_add(at_layer_add(at_layer("l"),
                                    at_roi_rect(0, 0, 1, 1, label = "a")),
                       at_roi_rect(5, 5, 6, 6, label = "a"))
  empty <- at_rois_overlap(lyr2)
  expect_equal(nrow(empty), 0L)
  expect_identical(names(empty), c("id_a", "id_b", "overlap_px", "jaccard"))
})

test_that("at_check_geometry detects every issue class", {
  targets <- c(
    self_intersect = "self_intersection", zero_area = "zero_area",
    degenerate = "degenerate", out_of_bounds = "out_of_bounds",
    na_coord = "na_coordinates", dup_vertex = "duplicate_vertices",
    ring_orientation = "ring_orientation"
  )
  for (nm in names(targets)) {
    ch <- at_check_geometry(broken_project(nm))
    expect_true(targets[[nm]] %in% ch$issue, info = nm)
  }
})

test_that("at_check_geometry is type-stable and clean projects pass", {
  ch <- at_check_geometry(demo_project())
  expect_s3_class(ch, "tbl_df")
  expect_equal(nrow(ch), 0L)
  expect_identical(names(ch), c("roi_id", "issue", "severity", "fixable"))
})

test_that("at_fix_geometry repairs invalid geometry and reports", {
  proj <- broken_project("self_intersect")
  expect_message(fixed <- at_fix_geometry(proj), "Repaired")
  expect_false("self_intersection" %in% at_check_geometry(fixed)$issue)
})

test_that("at_fix_geometry leaves unfixable issues and reports them", {
  proj <- broken_project("zero_area")
  fixed <- suppressMessages(at_fix_geometry(proj, verbose = FALSE))
  expect_s3_class(fixed, "annot_project")
})

test_that("geometry mutators do not modify their input", {
  r <- at_roi_rect(0, 0, 10, 10, label = "a")
  snapshot <- r
  invisible(at_snap(r, 2))
  invisible(at_flip_y(r, 50))
  expect_identical(r, snapshot)
})

# ---- Set operations, predicates and repairs (audit A16, C3, C5, C8, C14, C15)

test_that("set operations refuse ROIs at different levels (A16)", {
  big <- at_roi_rect(0, 0, 10, 10, label = "a")
  small <- at_roi_rect(0, 0, 5, 5, label = "a", level = 1)
  err <- tryCatch(at_roi_difference(big, small), error = identity)
  expect_s3_class(err, "at_validation_error")
  expect_identical(err$code, "MIXED_LEVELS")
  expect_error(at_roi_union(big, small), class = "at_validation_error")
  # Brought to one level first, the difference is empty, as it should be.
  same <- at_roi_rescale(small, to_level = 0)
  expect_warning(d <- at_roi_difference(big, same), "empty")
  expect_identical(at_roi_area(d), 0)
})

test_that("an empty set-operation result is a valid empty polygon (C3)", {
  a <- at_roi_rect(0, 0, 5, 5, label = "a")
  expect_warning(x <- at_roi_intersect(a, at_roi_rect(10, 10, 15, 15, label = "a")), "empty")
  expect_length(x$geometry, 1L)
  expect_identical(at_roi_area(x), 0)
  proj <- at_add_roi(at_project(tiny_image(), at_layer("l")), "l", x)
  expect_equal(nrow(at_rois(proj)), 1L)
  expect_s3_class(at_summary(proj), "annot_summary")
  expect_identical(at_check_geometry(proj)$issue, "empty_geometry")
  expect_warning(at_roi_difference(a, a), "empty")
})

test_that("polygon set operations stay polygonal (C8)", {
  # Touching squares intersect only along an edge: no area, no line ROI.
  expect_warning(
    x <- at_roi_intersect(at_roi_rect(0, 0, 5, 5, label = "a"), at_roi_rect(5, 0, 10, 5, label = "a")),
    "empty"
  )
  expect_identical(as.character(sf::st_geometry_type(x$geometry)), "POLYGON")
  # A polygon/line mix from the overlay keeps the polygonal part.
  mp <- sf::st_multipolygon(list(
    list(rbind(c(5, 5), c(15, 5), c(15, 15), c(5, 15), c(5, 5))),
    list(rbind(c(10, 0), c(20, 0), c(20, 2), c(10, 2), c(10, 0)))
  ))
  y <- at_roi_intersect(at_roi_rect(0, 0, 10, 10, label = "a"), at_roi_from_sf(mp, label = "a"))
  expect_identical(as.character(sf::st_geometry_type(y$geometry)), "POLYGON")
  expect_equal(at_roi_area(y), 25)
  expect_s3_class(at_roi_rescale(y, to_level = 1), "annot_roi")
  # A self-touching freehand trace repairs to a polygon, not a collection.
  spike <- rbind(c(0, 0), c(10, 0), c(10, 10), c(5, 10), c(5, 20), c(5, 10), c(0, 10))
  z <- suppressWarnings(at_roi_polygon(spike, label = "a"))
  expect_true(as.character(sf::st_geometry_type(z$geometry)) %in% c("POLYGON", "MULTIPOLYGON"))
})

test_that("derived ROIs do not inherit locks, review state or QuPath identity (C15)", {
  a <- at_roi_rect(0, 0, 5, 5, label = "a", locked = TRUE, review_status = "reviewed",
                   stain = "HE")
  a$attributes$qupath <- list(object_id = "uuid-1")
  u <- at_roi_union(a, at_roi_rect(3, 3, 8, 8, label = "a"))
  expect_null(u$attributes$locked)
  expect_null(u$attributes$review_status)
  expect_null(u$attributes$qupath)
  expect_identical(u$attributes$stain, "HE")
  r <- at_roi_ring(at_roi_circle(10, 10, 4, label = "a", locked = TRUE), outer = 2)
  expect_null(r$attributes$shape)
  expect_null(r$attributes$locked)
})

test_that("predicates and pairwise overlaps accept the image pyramid (C5)", {
  img <- new_annot_image("a.tif", "tiff", c(100L, 80L), 2L,
                         list(c(100L, 80L), c(25L, 40L)), 1L)
  r0 <- at_roi_rect(36, 0, 40, 4, label = "a")
  r1 <- at_roi_rect(9.5, 0, 10, 2, label = "a", level = 1) # level 0: x 38..40
  # Without the pyramid the scale is unknown (a power-of-two guess would put
  # r1 at x 19..20), so mixed levels are refused rather than guessed.
  expect_error(at_roi_overlaps(r0, r1), class = "at_validation_error")
  expect_true(at_roi_overlaps(r0, r1, image = img))
  expect_equal(at_roi_distance(r0, r1, image = img), 0)
  l <- at_layer("l"); l$rois <- list(r0, r1)
  expect_error(at_rois_overlap(l), "image")
  ov <- at_rois_overlap(l, image = img)
  expect_equal(ov$overlap_px, 8)
})

test_that("at_rois_overlap matches a brute-force pairwise check", {
  l <- at_layer("l")
  for (i in 0:7) l <- at_layer_add(l, at_roi_rect(i * 3, 0, i * 3 + 5, 5, label = "a"))
  ov <- at_rois_overlap(l)
  expect_equal(nrow(ov), 7L)              # each rect overlaps only its neighbour
  expect_true(all(ov$overlap_px == 10))
})

test_that("snapping repairs a collapsed geometry instead of storing it invalid (C14)", {
  expect_warning(s <- at_snap(at_roi_circle(5, 5, 0.3, label = "a"), grid = 1))
  expect_true(isTRUE(sf::st_is_valid(s$geometry)))
})

test_that("at_fix_geometry clips to bounds as an area and fixes orientation (C14)", {
  # A triangle reaching outside the image: clamping each vertex would distort
  # it; the clip keeps exactly the inside part.
  tri <- new_annot_roi(sf::st_sfc(sf::st_polygon(list(rbind(
    c(2, 2), c(14, 2), c(2, 14), c(2, 2)))), crs = sf::NA_crs_),
    id = "t", label = "a", level = 0L)
  l <- at_layer("l"); l$rois <- list(tri)
  fixed <- at_fix_geometry(at_project(tiny_image(), l), verbose = FALSE)
  g <- fixed$layers$l$rois[[1]]$geometry
  inside <- sf::st_intersection(tri$geometry, sf::st_sfc(sf::st_polygon(list(rbind(
    c(0, 0), c(10, 0), c(10, 10), c(0, 10), c(0, 0)))), crs = sf::NA_crs_))
  expect_equal(as.numeric(sf::st_area(g)), as.numeric(sf::st_area(inside)))
  expect_identical(as.character(sf::st_geometry_type(g)), "POLYGON")
  # Hole orientation and duplicate vertices are fixed, so the advertised
  # 'fixable' issues actually disappear.
  for (nm in c("ring_orientation", "dup_vertex")) {
    proj <- broken_project(nm)
    before <- at_check_geometry(proj)$issue
    after <- at_check_geometry(at_fix_geometry(proj, verbose = FALSE))$issue
    expect_true(length(before) > 0L, info = nm)
    expect_length(after, 0L)
  }
})

test_that("at_fix_geometry keeps an unrepairable sliver rather than emptying it", {
  proj <- broken_project("zero_area")
  expect_message(fixed <- at_fix_geometry(proj), "cannot be auto-repaired")
  expect_identical(fixed$layers$broken$rois[[1]]$geometry, proj$layers$broken$rois[[1]]$geometry)
})

test_that("at_check_geometry flags ROIs at levels the image lacks", {
  r <- new_annot_roi(sf::st_sfc(sf::st_point(c(1, 1)), crs = sf::NA_crs_),
                     id = "r", label = "a", level = 2L)
  l <- at_layer("l"); l$rois <- list(r)
  expect_true("level_out_of_range" %in% at_check_geometry(at_project(tiny_image(), l))$issue)
})
