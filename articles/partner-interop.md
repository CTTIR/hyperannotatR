# Working with qupflowR: handoffs, control and training data

![hyperannotatR logo](figures/logo.svg)![hyperannotatR
logo](figures/logo-dark.svg)

hyperannotatR and the qupflowR package (a QuPath bridge, analysis and
workflow package) exchange annotations, masks, hyperspectral metadata
and deep-learning datasets through a small, versioned contract. qupflowR
never reaches into hyperannotatR internals, Shiny state, `inst/` files
or the browser DOM; it uses the public functions below, the files they
write, or the optional local control service. This vignette describes
that contract from the hyperannotatR side.

## What this installation supports

``` r

caps <- at_interop_capabilities()
caps
#> <at_capabilities> hyperannotatR 0.3.0 for qupflowR
#>   I0 supported   file interchange (handoff directory)
#>   I1 supported   public R API
#>   I2 planned     loopback control service - implemented and tested locally; no qualified qupflowR client run recorded
#>   I3 planned     embeddable shiny.appobj - at_app() is implemented and tested locally; no qualified qupflowR embedding recorded
#>   digest d635a2101a97788c784d52220c1c4e3ff211965d1cb7d93c85d0953b274f9410
caps$profiles$I2[c("status", "implemented", "available", "reason")]
#> $status
#> [1] "planned"
#> 
#> $implemented
#> [1] TRUE
#> 
#> $available
#> [1] TRUE
#> 
#> $reason
#> [1] "implemented and tested locally; no qualified qupflowR client run recorded"
```

The profiles are:

| Profile | What it covers | Status rule |
|----|----|----|
| I0 | file interchange: handoff directories, QuPath GeoJSON, masks with legends | supported |
| I1 | public R API (`at_*` functions) | supported |
| I2 | loopback control service `annotatr-control-v1` | `planned` until qualified with a real qupflowR client; `unavailable` without httpuv/later |
| I3 | embeddable app object from [`at_app()`](https://cttir.github.io/hyperannotatR/reference/at_app.md) | `planned` until qualified; `unavailable` without shiny/bslib/shinyjs/htmlwidgets |

A capability is never advertised as supported because it merely exists.
The report carries a `digest` (SHA-256 of its canonical JSON) that
manifests and handshakes repeat, so a partner can bind its expectations
to exactly this set.

## Handoff directories

[`at_export_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_export_qupflowr.md)
writes a new, self-contained directory of neutral files:

``` r

proj <- at_example_project()
dest <- file.path(tempdir(), "qupflowr-handoff")
receipt <- at_export_qupflowr(proj, dest, formats = c("qupath_geojson", "mask_tiff", "manifest"),
                              overwrite = TRUE)
receipt$files[, c("path", "size_bytes", "format")]
#> # A tibble: 5 × 3
#>   path                                   size_bytes format        
#>   <chr>                                       <dbl> <chr>         
#> 1 annotations_qupath.geojson                   2870 qupath_geojson
#> 2 image.json                                   1824 image_json    
#> 3 manifest.json                                8409 manifest      
#> 4 masks/regions_labelled.tif                   2936 mask_tiff     
#> 5 masks/regions_labelled.tif.legend.json       1811 legend_json
receipt$handoff_digest
#> [1] "5f523be7b354a5eee7c42cf6f54ae9de76ce109723561883921ee4e20894bf11"
```

- `annotations_qupath.geojson` uses the QuPath 0.4+ dialect with a
  stable UUID per ROI and hyperannotatR’s ROI id, layer, source and
  coordinate level in `properties.metadata`.
- `masks/<layer>_labelled.tif` holds one integer value per ROI; its
  `.legend.json` joins values to ROI ids, labels and colours.
- `image.json` and `manifest.json` identify images by content hash and
  file basename only. No absolute path is used as identity.
- `integrity.json` inventories every other file (`path`, `size_bytes`,
  `sha256`, sorted by path). The **handoff digest** is the SHA-256 of
  its canonical JSON (keys sorted, no whitespace, integer sizes, no
  trailing newline) — the same rule qupflowR uses for its bundle digest.

Files are written to a hidden staging directory and moved into place
only when complete. An existing destination is replaced only with
`overwrite = TRUE`, and only if it is itself a handoff directory.

A session export writes each queue entry under `entries/<entry_id>/`.
Entry ids come from the session manifest’s stable `entry_id` (falling
back to `entry-0001`, … for older sessions), and the manifest’s ROI,
layer and file records carry the `entry_id` they belong to, so two
entries showing the same image stay separate. Project masks have the ids
`project:<layer>`.

### The manifest

``` r

man <- receipt$manifest
man[c("schema", "schema_version", "consumer", "object_kind")]
#> $schema
#> [1] "annotatr-handoff-v1"
#> 
#> $schema_version
#> [1] "1.1"
#> 
#> $consumer
#> [1] "qupflowR"
#> 
#> $object_kind
#> [1] "project"
str(man$coordinate_convention)
#> List of 7
#>  $ origin        : chr "top_left"
#>  $ x_axis        : chr "right"
#>  $ y_axis        : chr "down"
#>  $ units         : chr "px"
#>  $ level_scale   : chr "declared"
#>  $ pixel_centre  : chr "half_integer"
#>  $ plane_indexing: chr "zero_based"
man$images[[1]][c("image_id", "source_name", "width", "height", "n_bands", "transform_digest")]
#> $image_id
#> [1] "sha256:3fa00078c93c3a7d"
#> 
#> $source_name
#> [1] "example_tissue.png"
#> 
#> $width
#> [1] 512
#> 
#> $height
#> [1] 512
#> 
#> $n_bands
#> [1] 3
#> 
#> $transform_digest
#> [1] "9f3c4f1dfe0d1f127c2bd93ea92428bda102adc29cd80fd85cd936144e71c2dc"
man$annotations$annotation_revision
#> [1] "sha256:6b91babfc88f9fa8593075b60d31a11fb82d3fdb8c368c99e0fe76cffc065321"
```

The coordinate convention is explicit: pixel units, origin at the
top-left corner, `y` increasing downward, planes indexed from zero, and
the pixel coverage rule for masks. QuPath object hierarchy and native
ROI shapes, which hyperannotatR does not model, are reported as
`"unknown"` or `"approximated"` (circles and ellipses are polygons)
instead of being invented.

## Importing, staging and committing

[`at_import_qupflowr()`](https://cttir.github.io/hyperannotatR/reference/at_import_qupflowr.md)
reads only the neutral contract. It verifies the inventory (missing,
extra, duplicate, resized, altered and symlinked files), the manifest
schema and its major version, the id join between manifest and GeoJSON,
labels, mask dimensions, integer values and legend completeness. Any
failure is a classified error with a machine-readable `code` (for
example `DUPLICATE_ID`, `LEGEND_INCOMPLETE`, `MASK_INVALID`,
`FORMAT_UNRECOGNISED` or `INVALID_JSON`, which also covers duplicate
JSON keys); nothing is written and no analysis runs. Operating-system
metadata files that are not in the inventory (`.DS_Store`, `._*`,
`Thumbs.db`, `desktop.ini`) are ignored with a warning. The conversion
table’s `geometry_match` reports `"exact"` when the geometry is
byte-identical to its manifest record, `"equivalent"` when an export at
another pyramid level agrees with it within a relative `1e-9` after
rescaling, and `"changed"` otherwise.

``` r

report <- at_import_qupflowr(dest, expected_revision = at_annotation_revision(proj))
report$checks
#> # A tibble: 5 × 3
#>   check               status detail                                             
#>   <chr>               <chr>  <chr>                                              
#> 1 integrity           ok     5 files verified                                   
#> 2 manifest_schema     ok     1.1                                                
#> 3 annotations:project ok     3 ROIs joined by id at level 0                     
#> 4 masks               ok     1 masks: dimensions, integers and legends verified 
#> 5 expected_revision   ok     sha256:6b91babfc88f9fa8593075b60d31a11fb82d3fdb8c3…
```

Changes are applied in two explicit steps. Staging joins ROIs by id and
classifies each change. Reviewed or locked ROIs and locked layers,
including a locked target layer of a new or moved ROI, are never changed
automatically but reported as conflicts. ROIs whose ids were minted on
import, because the file carried none, are always staged as new ROIs:

``` r

partner <- report$objects$layers$regions
partner <- at_layer_add(partner, at_roi_rect(10, 10, 60, 60, label = "stroma", id = "from-partner"))
patch <- at_stage_qupflowr(proj, partner, expected_revision = at_annotation_revision(proj))
patch$operations
#> # A tibble: 4 × 5
#>   op        roi_id        layer   label    reason
#>   <chr>     <chr>         <chr>   <chr>    <chr> 
#> 1 unchanged roi_000000001 regions tumour   ""    
#> 2 unchanged roi_000000002 regions necrosis ""    
#> 3 unchanged roi_000000003 regions stroma   ""    
#> 4 create    from-partner  regions stroma   ""
```

Committing is idempotent: the same key replays the original receipt, a
reused key for a different patch is refused. When the patch targets a
project file, the file’s revision is checked again immediately before it
is replaced, and replacing an existing file requires `overwrite = TRUE`.

``` r

receipt <- at_commit_qupflowr(patch, idempotency_key = "vignette-commit")
receipt$new_revision
#> [1] "sha256:8850adbda3b979cd3e45d9541c93c712404adf3a8eb7633e659f1a7bb69fbde5"
at_commit_qupflowr(patch, idempotency_key = "vignette-commit")$replayed
#> [1] TRUE
```

## Hyperspectral metadata

Spectral images keep the format-independent tile contract
`[y, x, band]`. Metadata travels with them explicitly:

``` r

cube <- at_example_image("cube")
head(at_bands(cube), 3)
#> # A tibble: 3 × 7
#>   index name   wavelength unit   fwhm order wavelength_status
#>   <int> <chr>       <dbl> <chr> <dbl> <int> <chr>            
#> 1     1 Band 1       450  nm       NA     1 ok               
#> 2     2 Band 2       462. nm       NA     2 ok               
#> 3     3 Band 3       473. nm       NA     3 ok
at_hsi_meta(cube)[c("image_kind", "value_unit", "interleave", "byte_order", "header_bytes",
                    "calibration_digest", "window_read")]
#> $image_kind
#> [1] "spectral"
#> 
#> $value_unit
#> [1] "unknown"
#> 
#> $interleave
#> [1] "bsq"
#> 
#> $byte_order
#> [1] "little"
#> 
#> $header_bytes
#> [1] 0
#> 
#> $calibration_digest
#> [1] NA
#> 
#> $window_read
#> [1] TRUE
```

Raw values, reflectance, radiance, intensity and absorbance are never
mixed:
[`at_convert_values()`](https://cttir.github.io/hyperannotatR/reference/at_convert_values.md)
implements the named conversions and refuses to guess a missing
calibration. ENVI and TIVITA cubes are read window by window, so
opening, printing or displaying a cube does not load it;
[`at_read_stats()`](https://cttir.github.io/hyperannotatR/reference/at_read_stats.md)
reports the bytes read. A TIVITA `*_SpecCube.dat` is decoded only
through a declared
[`at_tivita_profile()`](https://cttir.github.io/hyperannotatR/reference/at_tivita_profile.md)
or a `<cube>.tivita.json` sidecar. Cubert `.cu3s` files need `cuvis.r`
and the CUVIS SDK; without them the backend reports itself unavailable
and an SDK-written ENVI export is the portable fallback. Display
products from
[`at_band_view()`](https://cttir.github.io/hyperannotatR/reference/at_band_view.md)
(ratios, normalised differences, band means) carry their parent digest
and band list and are never used as analysis input.

## Deep-learning training datasets

``` r

sess <- at_example_session(3)
for (i in seq_len(3)) sess$projects[[i]] <- at_example_project()
ds <- at_training_export(sess, file.path(tempdir(), "training-dataset"), tile_size = 128,
                         mask_type = "labelled", seed = 11, overwrite = TRUE)
#> Registered S3 method overwritten by 'stars':
#>   method                  from
#>   st_interpolate_aw.stars sf
ds$manifest$split_policy$algorithm
#> [1] "groups ranked by sha256('<seed>:<group_id>'), cut by cumulative fractions rounded half up"
ds$manifest$counts[c("tiles", "tiles_by_split", "excluded")]
#> $tiles
#> [1] 48
#> 
#> $tiles_by_split
#> $tiles_by_split$train
#> [1] 48
#> 
#> $tiles_by_split$validation
#> [1] 0
#> 
#> $tiles_by_split$test
#> [1] 0
#> 
#> 
#> $excluded
#> $excluded$partial
#> [1] 0
#> 
#> $excluded$empty
#> [1] 0
ds$checks
#> # A tibble: 7 × 3
#>   check              status detail                                              
#>   <chr>              <chr>  <chr>                                               
#> 1 integrity          ok     inventory verified                                  
#> 2 split_leakage      ok     1 groups, 3 images, no shared source across splits  
#> 3 mask_dimensions    ok     0 of 48 tiles with wrong or unreadable dimensions; …
#> 4 label_range        ok     0 of 48 tiles with codes outside the legend         
#> 5 overlap            ok     0 ambiguous (overlapping) pixels in included tiles  
#> 6 mask_roi_roundtrip ok     0 of 20 sampled tiles differ after mask -> ROI -> m…
#> 7 manifest_schema    ok     1.1
```

Splits are assigned per group, so tiles of one group never occur in two
splits. The default group is the image, identified by its content hash
(including any non-default series, plane or measurement). The three
example entries are copies of one picture, so they form a single image
group and all land in one split: tiles of one image never leak across
splits. Distinct images spread over the splits. Group by `sample_id` or
`subject_id`, supplied in `groups`, when several images come from one
sample or one patient; entries that show the same pixels must still
share a split, and
[`at_training_check()`](https://cttir.github.io/hyperannotatR/reference/at_training_check.md)
reports an image found in two splits as leakage. The manifest records
tile size, overlap, level, pixel origin, coverage rule, class legend
(background `0`), band list with wavelengths and FWHM, value unit,
calibration and transform digests, annotation revisions and review
status counts.
[`at_training_check()`](https://cttir.github.io/hyperannotatR/reference/at_training_check.md)
re-verifies the inventory, split leakage, mask dimensions, label range
and a mask-to-ROI round trip.

Model predictions come back as staged annotations. They must match the
image dimensions and use only codes from the label map; reviewed
annotations are never overwritten:

``` r

pred <- matrix(0L, 512, 512)
pred[20:80, 30:120] <- 1L
staged <- at_training_import(proj, pred, label_map = c(tumour = 1L),
                             model = list(name = "example-unet", version = "0.1",
                                          sha256 = strrep("0", 64)))
staged$summary
#> $create
#> [1] 1
#> 
#> $update
#> [1] 0
#> 
#> $unchanged
#> [1] 0
#> 
#> $delete
#> [1] 0
#> 
#> $conflict
#> [1] 0
```

Training itself remains an external, optional workflow.

## The control service

A partner process can drive a running app through the loopback service.
It is off unless started, binds only to `127.0.0.1`, authenticates with
a random bearer token that expires, rejects browser-origin requests and
oversized bodies, resolves file references only below its root, and
offers no endpoint that evaluates R, shell or Python code. Tokens come
from the operating system’s random source (`/dev/urandom`) or, where
that does not exist (Windows), from the optional `openssl` package;
without either, the service refuses to start.

``` r

handle <- at_control_start(at_example_session(2), serve = FALSE)
state <- at_control_state(handle)
state$state_revision
#> [1] "0"
at_control_command(handle, list(operation = "context.goto", payload = list(queue_index = 2),
                                expected_revision = state$state_revision))$entry_id
#> [1] "entry_at_2f1c6ea65622_000000005"
vapply(at_control_events(handle)$events, `[[`, character(1), "type")
#> [1] "service.started" "image.changed"
at_control_stop(handle)
```

In a real integration the app runs in its own process:

``` r

handle <- at_control_start(session, token_file = "/run/user/1000/annotatr.token")
shiny::runApp(at_app(control = handle))
# ... in the partner process:
remote <- at_control_connect(manifest_path, "/run/user/1000/annotatr.token")
```

Every mutation carries a `request_id`, the `expected_revision` it is
based on, an `idempotency_key` and the SHA-256 of its canonical payload.
A stale revision is a conflict; a lost response is resolved with
[`at_control_request_status()`](https://cttir.github.io/hyperannotatR/reference/at_control_request_status.md),
and re-sending with the same key never applies a command twice. Events
are read with a cursor; a cursor from another instance or older than the
retained buffer yields `resync_required = TRUE`.

A few further rules matter to clients:

- `session.load` refuses with `UNSAVED_CHANGES` (409) while the current
  session has unsaved or staged edits, unless the payload sets
  `discard_unsaved: true`. A loaded session gets its own output
  directory under `<root>/sessions/`, reported as the relative
  `session_dir`.
- Re-sending an idempotency key whose record has already been evicted
  returns `IDEMPOTENCY_EXPIRED` (409) instead of running the command
  again.
- `mask.preview` refuses masks larger than
  `options(hyperannotatR.control_mask_max_pixels)` (default 4096^2
  pixels) with `MASK_TOO_LARGE` (413).
- `GET /v1/state` reports `image_id: null` for unvisited queue entries
  larger than `options(hyperannotatR.control_hash_max_bytes)` (default
  256 MiB) rather than hashing them while the app waits.
- `close` is not revision-checked. Once the token has expired, the
  listener shuts down.
- Error bodies carry the condition `class` alongside the `code`. Paths
  in errors are reported relative to the root, never as absolute paths.
- The remote client ignores `http_proxy`/`https_proxy` and never follows
  redirects, so the token only ever goes to the loopback address.
- On Windows the operating system does not enforce the token file’s
  owner-only permission; keep it in a directory only you can read.

The JSON Schemas for all documents ship with the package:

``` r

basename(list.files(system.file("schema", package = "hyperannotatR"), recursive = TRUE))
#>  [1] "command.schema.json"           "event.schema.json"            
#>  [3] "events-page.schema.json"       "handshake.schema.json"        
#>  [5] "health.schema.json"            "request-record.schema.json"   
#>  [7] "response.schema.json"          "state.schema.json"            
#>  [9] "integrity.schema.json"         "manifest.schema.json"         
#> [11] "training-manifest.schema.json" "tivita-profile.schema.json"
```

## Versions and migration

Schema versions are independent of the package version. Readers accept
any `1.x` version, reject an unknown major version and keep unknown
optional data only under `extensions`. hyperannotatR 0.2.0 introduced
`annotatr-handoff-v1`, `annotatr-control-v1`, `annotatr-training-v1` and
`annotatr-hsi-v1`; they are now at version `1.1`. The `integrity.json`
format stays at `1.0`, because its digest rule is shared with qupflowR.
Existing 0.1 files remain readable: legacy QuPath GeoJSON
(`object_type`, `colorRGB`) is imported, and
`at_write_qupath(dialect = "legacy")` still writes it.
