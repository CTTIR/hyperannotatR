# Scope of roadmap work packages T15–T18 (reviewed specifications)

These specifications were produced on 2026-10-18 by an analysis and skeptical-review pass over the code at `649cf49`, under the package's former name annotatR and before two decisions:

- the package became hyperspectral-first;
- histology and cell annotation moved to segmantR.

Apply them through the re-scoping in [HANDOVER.md](HANDOVER.md). Notes on reading them:

- File paths and line numbers refer to that tree.
- Option names `annotatR.*` are now `hyperannotatR.*`.
- The finding ids were later registered as A34 (sf namespace import) and A35 (planar-separate TIFF refusal); both are fixed in 0.3.0.
- The probe scripts the specifications cite (`<scratch>/...`) were temporary and are not kept.

## T15 - Real windowed reads behind the existing backend contract. Remaining scope on main 649cf49, reviewed and corrected on 2026-10-18. Five parts: (1) refuse planar-separate TIFFs now (A34); (2) a metadata-only TIFF scan with a budgeted eager fallback; (3) windowed plain and pyramidal TIFF through an isolated GDAL (terra) worker; (4) finished capability and lifecycle handling; (5) a portable fresh-process resource harness.

Estimated effort: 70 focused hours.

### Current state

REVIEW BASIS. This review was read-only. Probes are in <scratch> Host: macOS arm64, R 4.6.1, terra 1.9.50, GDAL 3.13.3, ps 1.9.3, processx 3.9.0, callr 3.8.0, tiff 0.1.12, magick 2.9.1. There is no Java runtime, so RBioFormats cannot run here. Claims from the original spec that held up are kept. Changes are tagged [corrected] or [new].

1. envi (verified). backend-envi.R:.envi_read reads only the header. It goes through .parse_envi_hdr (1 MiB cap) and io-window.R:.window_read_raw, which counts the bytes. Payload length is checked by .envi_check_payload, and the handle holds paths plus the parsed header. Windows run .envi_tile -> .envi_read_window -> .envi_read_distinct under .window_budget. .read_envi_data has no callers.
   - Rerun of harness_envi_tivita.R, 512^2 vs a sparse 32768^2 (6 GiB) cube: open read 73/77 header bytes, the window read 16384 bytes, decoded bytes were 98304.
   - The 'peak above baseline RSS' was 2.27/2.09 MiB and was the same after open and after the window. So the read never raised the process high-water mark above the headroom it already had.

2. tivita (verified). The SpecCube branch reads 12 header bytes at open. Each column of a window is one contiguous run. 512^2 and 8192^2 gave identical byte counts (12 open, 49152 window).

3. ometiff.
   - The reader matches the spec: backend-tiff.R:.ometiff_read opens metadata only, io-window.R:.ome_window reads native subsets, and per-image meta reports window/native.
   - Two declarations contradict this. zzz.R:.register_backends declares FALSE/FALSE, samples 'unqualified', io 'eager'. interop-capabilities.R:.hsi_backend_caps reports window_read=FALSE.
   - [corrected] The archived Linux evidence is planning/evidence/implementation-2026-09-10/t15/ome-{512,16384}.result.R (VmRSS). Open: +220.6 MiB at 512^2 vs +270.6 MiB at 16384^2. Window: +1.6 vs +30.9 MiB. The spec's '+283 MiB' and '+32 MiB' mixed MB with MiB and hid that the OME open itself differs by 50 MiB between the two sizes.

4. tiff (eager; the main gap).
   - backend-tiff.R:.tiff_read -> .tiff_raw_read -> io-tiff-process.R:.tiff_read_isolated decodes every directory in a one-shot Rscript child. The result comes back as an uncompressed RDS and is held as double arrays in handle$levels. .tiff_tile subsets in memory. There is no budget check before decoding.
   - Eager peak: an 8192^2 uint16 file produced a 2.67 GiB R heap for 512 MiB of doubles (about 5.2x). Rerunning the prototype, eager 1024^2 added 38 MiB.
   - [new] .tiff_raw_read wraps the decoder in suppressWarnings(), so today no libtiff warning reaches the user. For example, tiff::readTIFF raises the ExtraSamples warning three times on inst/extdata/example_multiplex.tif.
   - A34 reproduced (p1_planar.R): a hand-written planar-separate uint16 TIFF reads as dtype uint16 with 57 of 60 samples 0 and no error. A contiguous control with the same tags decodes exactly (p2_contig_control.R), so the cause is PlanarConfiguration=2. GDAL decodes the file exactly.
   - [new] tiff::readTIFF(info=TRUE) already returns attr 'planar.config' = 'separate', so the refusal needs no IFD scanner.
   - [new] The tiff branch of backend-raster.R:.raster_read (used when magick is absent) gives the same 57/60 zeros. It calls .tiff_read_isolated(path, as.is = FALSE) without info=TRUE.
   - mask-io.R:.read_mask_matrix also uses .tiff_raw_read but accepts only single-sample planes, which planar layout cannot corrupt.
   - Accepted today: uint8, int8 (verified exact, p13_int8.R), uint16, int16, float32; photometric MinIsBlack or RGB. int32/uint32 fail the 8/16-bit integer rule. float64 is refused by the decoder itself ('64 bits/sample ... unsupported in direct mode').
   - tiff::writeTIFF writes one strip per page (RowsPerStrip = height).

5. raster. Eager, with display conversion and eager capabilities, and no budget check. [new] magick 2.9.1 exports no ping-style read, so any preflight after image_read comes after ImageMagick has already decoded the image.

6. cuvis. Eager whole-cube read through the SDK (cuvis_get_cube). The SDK is unavailable here.

7. Lifecycle.
   - at_backend_register takes a static capabilities list and close_fn. at_close_image calls close_fn unprotected and mints a 'closed' identity. .handle_cache_clear is a no-op.
   - [corrected] Each closed-image at_tile call costs 149 bytes: 125 header bytes from .reopen_image plus 24 window bytes. backend.R:at_tile runs .reopen_image before the tile-cache lookup. Keying the cache by the caller's identity alone therefore still re-reads the header on every call (p5_closed.R: cumulative 149, then 274).
   - at_read_stats(closed)$tiles reports 0, because hsi-meta.R:.read_stats_key uses the reopened identity.
   - [new] backend.R:at_read_image copies the registry capabilities into img$meta when a reader sets none. at_backend_list and at_image_capabilities index the registry capabilities as a list.
   - io-window.R:.memory_snapshot duplicates persistence.R:.holds_pixel_arrays.
   - .read_telemetry_add turns an unknown key into numeric(0).

8. Measurement. Telemetry exists, and test-windowed-readers.R checks bytes counted from before at_read_image. Nothing checks memory. tests/qualification/window-resources.R reads memory from /proc, so it runs on Linux only. New probe findings on the proposed metrics:
   - (a) On macOS, ps_memory_full_info() for another process returns 'Permission denied' (p6_ps.R). The worker must report its own memory.
   - (b) Under pkgload::load_all, the roughly 40-50 MiB 'R-heap peak' is churn from the JIT compiling closures that load_all leaves uncompiled (Ncells). It is not read cost: with compiler::enableJIT(0), open plus a 2x2 tile costs 1.3-1.5 MiB (p17b_nojit.R).
   - (c) With the JIT on, the baseline headroom (maxrss minus rss) varied from 2.27 to 16.5 MiB between fresh processes running identical code. That alone produced a 12.7 MiB small-vs-large difference in the spec's main_peak_above_rss metric (3.83 vs 16.5), which would fail its 8 MiB tolerance. With the JIT off, the headroom was 2.08-2.09 MiB in all six runs (p14_warm.R, p14b_nojit.R).
   - (d) The worker's absolute maxrss was 202 MiB in one session and 222 MiB in another. It is dominated by loading terra and GDAL, and is consistent within a session.
   - (e) VALIDATION.md specifies a fixed 256x256 window. The qualification script and the prototypes use 64x64.

9. [new] 0.2.0 context the design must respect.
   - sf and stars are Imports, so GDAL is loaded in the main process from package load. terra is in Suggests, and is loaded in the main process only by at_mask(engine='terra'); the default engine is 'stars'.
   - Several 0.2.0 records are visible to partners. at_interop_capabilities() digests .hsi_backend_caps(), and training.R and interop-manifest.R record that digest. interop-manifest.R records at_hsi_meta()$window_read and $nodata. interop-handoff.R records at_read_stats().
   - widget-canvas.R:.preview_bands reads the display level in full-width row chunks of at most 64e6 bytes.
   - README.Rmd still says TIFF needs the tiff package and is decoded whole.
   - test-backend-tiff.R expects TIFF_AMBIGUOUS for pages with different sample counts.
   - new_annot_image() coerces dims, level_dims and n_bands to integer.
   - at_example_image('multiplex') overwrites band_names after reading. That is an existing reopen mismatch for any backend, not a T15 issue.

WHAT THE T15 ACCEPTANCE CRITERIA STILL LACK:
- A windowed TIFF path. The vignette says 'tiff: Eager / memory subset ... no window claim'.
- A portable memory measurement taken before at_read_image, using the VALIDATION 256x256 window at two file sizes.
- Consistent tiff and ometiff capability declarations.
- Accounting and caching for closed or reopened images.
- An explicit, budgeted eager fallback.
- The A34 refusal.
- OME qualification on main (blocked here).
- Measured, rather than index-derived, TIFF bytes. These exist only on Linux.

### Design

PHASES. Each phase can be merged on its own.
- P1: A34 refusal.
- P2: IFD scan, metadata-only open, budgeted eager fallback, capability and lifecycle fixes.
- P3: GDAL worker and windows.
- P4: harness, lanes, docs and evidence.

P1. A34 REFUSAL. No user decision is needed: refusing an unqualified encoding follows the existing rule.
- backend-tiff.R:.tiff_raw_read returns TIFF_UNSUPPORTED when attr(a, 'planar.config') == 'separate' and samples.per.pixel > 1.
- backend-raster.R:.raster_read calls .tiff_read_isolated(path, as.is = FALSE, info = TRUE) and applies the same refusal.
- Record A34 in planning/ADDITIONAL-FINDINGS.md.
- Correct decoding of planar-separate files arrives later with the GDAL engine.

A. ENGINE.
- terra/GDAL runs only in the worker. Every open uses terra::rast(src, noflip=TRUE, raw=TRUE, lyrs=ub). lyrs works with both the GTIFF_DIR form and the nested vrt form, including reordering.
- Exactness verified on reference-{uint8,uint16,int16,float32,int32,uint32,float64,rgb}.tif, including INT_MIN, 4294967295, NaN and +/-Inf. int8 (INT1S) and planar-separate files are also exact.
- [corrected] terra returns integer storage for 8/16-bit data, and also for INT4S windows whose values fit R integers. It returns double only otherwise, so the worker always coerces explicitly.
- Rejected alternatives:
  - stars, and sf::gdal_read underneath it (an Import): sf maps NaN to NA (p11_sf.R), which breaks the A26 float expectations, and stars applies scale/offset.
  - The tiff package: it cannot read windows and it mis-decodes planar-separate files.
- Required GDAL features: the Int8 data type and the vrt:// a_nodata option (GDAL 3.7 or later). The init self-test checks these; no version number is hard-coded.
- Raw-semantics guards (kept):
  - noflip=TRUE.
  - GDAL_PAM_ENABLED=NO and GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR.
  - IFDs with a NoData tag open as vrt://GTIFF_DIR:<ifd>:<path>?a_nodata=none. Verified: the plain form returns NA for stored 0; the vrt form returns 0.
  - Each level is addressed explicitly as GTIFF_DIR:<ifd>:<path>. Levels 1-3 of the multiplex example open this way.
- [new] Environment sanitizing. The worker pins GTIFF_IGNORE_READ_ERRORS=NO and strips GDAL_*, GTIFF_*, CPL_* and VSI_* variables from its environment. Probe p16_ignore.R: with GTIFF_IGNORE_READ_ERRORS=YES inherited, a truncated tile returned 1024 values, 512 of them zero, with only a warning.
- [new] Whitelist, checked by the scan before any worker call:
  - Compression: 1 none, 5 LZW, 8 and 32946 Deflate, 32773 PackBits.
  - Predictor: 1, or 2 for integer samples only.
  - JPEG (7): photometric RGB only, subject to the user decision.
  - Everything else returns TIFF_UNSUPPORTED: ZSTD, LZMA, WEBP, LERC, JPEG-XL, old-style JPEG, CCITT, JPEG 2000, predictor 3, and missing byte-count tags. Without this, GDAL would silently accept lossy codecs under the raw-scalar-v1 contract.

B. ISOLATION.
- Transport: a persistent processx worker started as Rscript --vanilla --default-packages=NULL <script> <private dir>. Requests are JSON lines on stdin. Responses are uncompressed RDS files in a private 0700 directory, each announced by an id line on stdout. The master waits with poll_io and a deadline.
- Measured again on this host (probe19_pipe2.R): start plus terra load 2.16 s, ping 0.4 ms, 64x64x4 window 8.4 ms, 512x512x4 window 72 ms. Deadline-and-kill works.
- Alternatives:
  - callr::r_session costs 46 ms per call and fails to start with --default-packages=NULL (p12_rsession.R).
  - PSOCK workers exit when idle only after their configured timeout; the real blocker is that per-request deadlines need parallel::: internals.
- [corrected] Rationale. GDAL is already in the main process through sf. The worker keeps TIFF pixel decoding and libtiff handler state out of the main process, and makes decode memory killable and measurable. The magick-then-read abort reproduces with the tiff package (exit 134) and not with in-process terra (crash_*.log).
- [new] Protocol robustness:
  - The master accepts only the pending request's id line and ignores any other stdout line. The worker writes nothing to stdout except ids; everything else goes to its log.
  - A timeout or an interrupt during a request (for example setTimeLimit) kills the worker. The next call restarts it, so a worker with an abandoned request is never reused.
  - The worker handle records the owner pid. A forked child (mclapply) never writes to or stops an inherited worker; it starts its own.
  - The worker runs with TMPDIR inside the master's session tempdir and is stopped with a 'quit' request, with kill only after a grace period, so no Rtmp* directories are left behind (R CMD check flags those).
  - The request handler is a package function deparsed into the script, so it can be unit-tested in a callr child and counted by covr.

C. METADATA-ONLY OPEN (new R/io-tiff-ifd.R).
- The walker is as in the spec: bounded, pure R, classic and BigTIFF, II and MM byte order, all reads through .window_read_raw. Limits: annotatR.tiff_max_directories=1024, at most 4096 entries per IFD, description at most 1 MiB, at most 4096 values per small-tag array. IFD loops, offsets beyond EOF and a short header abort. Offset/bytecount array descriptors are kept and their counts checked against the expected block counts.
- Prototype cost: 146 header bytes, the same for 1024^2 and 32768^2 tiled files.
- Parity rules, made explicit:
  - dtype must be uint8, int8, uint16, int16 or float32 (int32/uint32/float64 depend on the user decision). Photometric must be 1 or 2.
  - A dtype mismatch between IFDs gives TIFF_UNSUPPORTED.
  - TIFF_AMBIGUOUS covers a different sample count between IFDs (the existing 'mixed.tif' test), any level dimension larger than the previous level after a stable decreasing-area sort, and equal dimensions.
  - Mask IFDs, palette, YCbCr, min-is-white, float16 and 1/4/12-bit samples give TIFF_UNSUPPORTED.
  - Band names come from the first main-chain IFD in file order (before the size sort), with ImageDescription truncated at the first NUL as libtiff does. Only that IFD's description is read.
  - dims and level_dims are integer, through new_annot_image.
- Handle: list(windowed=TRUE, path, engine='gdal', endian, bigtiff, layout=<per level: ifd, width, length, tiled, block, compression, predictor, planar, offset/bytecount descriptors, nodata>, files=.persisted_source_files(c(image=path))). It is called layout rather than levels so array handles and window handles cannot be confused.
- Meta:
  - window_read=TRUE.
  - capabilities = .window_capabilities('native') plus additive engine='gdal', isolation='process', granularity='block', per-level block and compression, and lifecycle='persistent worker; dataset opened per request'. io stays within the documented vocabulary rather than adding 'native-isolated'.
  - meta$nodata holds the GDAL_NODATA value: recorded, never applied, the same contract as ENVI's data ignore value. Orientation and ignored tags go under meta$tiff.
- Engine selection: new option annotatR.tiff_engine = 'auto' | 'gdal' | 'eager'.
  - 'auto' uses the engine when terra and processx are installed and no engine init failure has been recorded this session; otherwise the eager reader when tiff is installed.
  - Installation is checked with find.package, never requireNamespace('terra') in the main process.
- Opening never starts the worker.

D. WINDOW READ.
- .tiff_tile dispatches on handle$windowed. Array handles (legacy snapshots, eager reads) keep the in-memory subset.
- Steps, as in the spec:
  1. Take the sorted distinct bands and apply .window_budget.
  2. Apply the block model.
  3. Check the pre-decode budget, the summed decoded bytes of the intersecting blocks against annotatR.max_read_bytes, before any worker call.
  4. Read only the offset and bytecount entries of the intersecting blocks. Offsets past EOF give PAYLOAD_SHORT; a bytecount of 0 is refused.
  5. Send the worker request with {size, mtime} and the expected datatype and dims. The worker re-checks both.
  6. The master checks the contract, maps bands back to the requested order and sets the file_bytes attribute.
  7. at_tile's existing source re-check catches a file replaced mid-read.
- [corrected] Block model:
  - Tiled: the tile.
  - Stripped: RowsPerStrip, or the full height when the tag is absent. Exception: contiguous, uncompressed and exactly one strip uses rows = min(height, max(1, floor(8192 / row_bytes))). libtiff chops the strip only when that reduces the row count.
  - Planar-separate with one strip per plane: the whole plane.
  - Contiguous layouts count all samples; separate layouts count only the requested planes.
  - Verified against GDAL 'Block=' (p7_blocks.R, p19_strips.R): 3000x2; 3000x1 (RGB uint16); 1000x8; 8192x1; 9000x1; 100x10 (no chop); 3000x7 (RowsPerStrip 7); 1000x900 (single-strip LZW and PackBits); 3000x2000 (planar).
- [new] Block check in the worker. The worker reads GDAL's actual block size for the opened level from terra::describe 'Block=' (3.5 ms, cached per path, signature and IFD). If it differs from the master's model, the request fails closed with BACKEND_CONTRACT, so a different libtiff/GDAL build cannot silently invalidate the budget.
- [corrected] Messages:
  - .tiff_raw_read suppresses all warnings today. At its default level, terra surfaces only GDAL error-class messages plus its own '[rast] unknown extent'; libtiff directory warnings are not surfaced (the multiplex example yields only 'unknown extent').
  - The worker sets terra::gdal(warn=3) explicitly and drops 'unknown extent'.
  - Any other GDAL message during open or read fails the request (those messages are error-class), even when GDAL returned values. Nothing is forwarded as an R warning.
- [new] Transfer. The worker returns native-width storage (integer up to 16 bits, double otherwise) and the master converts to double. This halves worker peak memory and RDS traffic.
- Telemetry:
  - Keys: native_window_calls, native_block_bytes (index-derived), decoded_bytes, worker_starts, worker_requests.
  - native_os_read_bytes accumulates only measured values (Linux /proc/self/io rchar) and never adds NA to the global counter.
  - The TIFF path does not touch native_file_bytes.

E. WORKER LIFECYCLE (new R/io-gdal-worker.R).
- Functions: .gdal_engine_status() (install check plus any recorded init failure), lazy .gdal_worker_get(), .gdal_worker_call(), .gdal_worker_stop().
- Init sends .libPaths() and the pinned GDAL config: PAM NO, READDIR EMPTY_DIR, GDAL_CACHEMAX from annotatR.gdal_cache_mb (default 64), GDAL_NUM_THREADS=1, GTIFF_IGNORE_READ_ERRORS=NO. It records pid, versions and initial rss/maxrss, and runs the self-test: a 1x1 NoData TIFF read through vrt a_nodata=none must return the stored value, and the INT1S datatype must be available.
- Start deadline: option annotatR.gdal_worker_start_timeout (60 s). Request deadline: annotatR.tiff_timeout, validated as in .tiff_read_isolated. There is no automatic retry.
- Datasets are opened and closed per request, and close_fn has nothing to release per image.
- Test-only 'sleep' and 'abort' ops run only with ANNOTATR_TEST_HOOKS=1.
- [new] An init or self-test failure surfaces at the first window as CAPABILITY_UNAVAILABLE. The message names the failed check and the annotatR.tiff_engine option. The failure is cached for the session, so later opens choose the eager reader and at_backend_list shows it.
- terra, GDAL and libtiff versions go into telemetry and evidence once known.

F. FALLBACK, CAPABILITIES, LIFECYCLE.
- Eager fallback .tiff_read_eager:
  - Scan first, so the A34 and whitelist refusals apply.
  - Then .read_budget(8 x samples over all levels) before the decoder is spawned. The budget counts decoded doubles, as for ENVI and NPY; the vignette documents the measured peak of about 5x.
  - Eager capabilities.
- .tiff_available() is unchanged (the tiff package; masks depend on it). .tiff_backend_available() means the engine is usable or tiff is installed.
- [corrected] Registry:
  - capabilities stays a list. at_backend_register gains an optional additive capabilities_fn argument, stored as a backend element. at_backend_list(), at_image_capabilities() and at_read_image() evaluate it inside tryCatch and fall back to the list. A function is never stored in image meta.
  - tiff: the list is the eager declaration; capabilities_fn reports the current engine state.
  - ometiff: TRUE/TRUE, io 'native', samples raw-scalar-v1. This is what the implemented reader does and what its per-image meta already reports. Qualification stays in at_interop_capabilities: status 'planned' with an empty qualified_with.
- .hsi_backend_caps: tiff window_read = engine usable, with the engine recorded; ometiff window_read=TRUE with status 'planned'. It never loads terra. NEWS states that the capability digest changes.
- at_close_image runs close_fn inside tryCatch, turns failures into a warning, and always releases the handle.
- [corrected] at_tile caching for closed images. When the image has no handle, a stat-only .source_status() is 'available' and the descriptor is not .composite_unverified(), look up the tile cache under the caller's cache_identity before .reopen_image. On a miss, reopen and read, then store the tile and the read stats under the caller's identity.
- .memory_snapshot is replaced by .holds_pixel_arrays. .read_telemetry_add aborts on unknown keys.
- Optional raster preflight: before decoding where a header parse exists (PNG IHDR, the TIFF scan); otherwise after magick::image_read and before array conversion, documented as post-decode.

G. MEASUREMENT HARNESS (tests/testthat/helper-resources.R:measure_fresh_read).
- Runs in a callr::r child loaded with fresh_loader() after compiler::enableJIT(0), or against the installed byte-compiled build.
- Baseline, taken before at_read_image: .gdal_worker_stop(); .tile_cache_clear(); .read_telemetry_reset(); gc(); gc(reset=TRUE); ps::ps_memory_full_info().
- Window: a fixed 256x256 window as VALIDATION.md specifies, both tile-aligned and tile-crossing.
- Recorded:
  - headroom0 = maxrss0 - rss0.
  - main_peak_excess = max(0, maxrss_after - maxrss0).
  - R-heap Vcells and Ncells max-used deltas, kept separate.
  - open and window binary bytes, native_block_bytes, decoded bytes.
  - The worker's own rss/maxrss before and after the request, and worker_window_excess.
  - On Linux: the per-request VmHWM after writing '5' to /proc/self/clear_refs, plus the rchar delta.
  - Whether terra is loaded in the main process.
  - Elapsed time for open, first window (including worker start) and warm window. Recorded, not asserted.
  - Versions and hardware.
- Structural assertions:
  - Open and window bytes are identical across sizes.
  - decoded bytes = 8 x window elements.
  - headroom0 <= 16 MiB; otherwise the run fails as inconclusive.
  - main_peak_excess <= 8 MiB at both sizes.
  - Vcells delta <= 3 x window decoded bytes + 4 MiB.
  - Tiled worker_window_excess <= 16 MiB at both sizes.
  - Negative control: eager 4096^2 uint16 gives a Vcells delta >= 128 MiB.
- Prototype rerun, tiled TIFF 1024^2 vs 32768^2: main peak +1.59/+1.58 MiB, worker about 222 MiB for both (the spec's earlier session measured 203 MiB), 146 header bytes, 131072 block bytes for both.
- Large fixtures are sparse files, with literal formula values written only in the tiles the window touches.

### Files

- `R/backend-tiff.R`: P1: .tiff_raw_read refuses planar.config == 'separate' with more than one sample (TIFF_UNSUPPORTED, A34).
P2/P3:
- .tiff_read becomes a metadata-only open: scan, whitelist, parity rules, layout handle with windowed=TRUE, capabilities with an additive engine/isolation/granularity, meta$nodata, and engine selection through the annotatR.tiff_engine option.
- New .tiff_window: band dedupe, output and pre-decode block budgets, block index, worker request, contract check, band reorder, file_bytes attribute, telemetry.
- .tiff_tile dispatches on handle$windowed and keeps the array subset for array handles.
- New .tiff_read_eager: scan, then .read_budget preflight, then .tiff_raw_read.
- New .tiff_backend_available(); .tiff_available() stays unchanged.
- `R/backend-raster.R`: P1: the tiff branch calls .tiff_read_isolated(path, as.is = FALSE, info = TRUE) and refuses planar-separate multi-sample files (A34).
Optional: a byte-budget preflight before decoding where a header parse exists (PNG IHDR, TIFF scan), otherwise after magick::image_read and before the double-array conversion.
- `R/io-tiff-ifd.R`: New file.
- .tiff_scan(): bounded IFD walker for classic and BigTIFF, II and MM byte order; all reads through .window_read_raw.
- .tiff_levels_from_scan(): parity rules with explicit codes. Description taken from the first main-chain IFD, truncated at the first NUL.
- .tiff_check_codec(): compression and predictor whitelist.
- .tiff_effective_blocks(): the corrected GDAL block model.
- .tiff_block_index(): reads only the entries for intersecting blocks; PAYLOAD_SHORT; bytecount 0 refused.
- Options annotatR.tiff_max_directories and annotatR.tiff_max_description_bytes.
- `R/io-gdal-worker.R`: New file.
- Functions: .gdal_engine_status() (find.package check plus session-cached init failure), .gdal_worker_get(), .gdal_worker_call(), .gdal_worker_stop().
- The request handler is a package function deparsed into the worker script.
- processx transport: JSON-line requests; RDS responses in a private 0700 dir announced by id lines; only the pending id is accepted; poll_io deadline.
- Kill and lazy restart after a timeout or interrupt; owner-pid fork guard.
- Environment: TMPDIR inside the session tempdir; GDAL_*/GTIFF_*/CPL_*/VSI_* variables stripped; pinned GDAL config including GTIFF_IGNORE_READ_ERRORS=NO; terra::gdal(warn=3).
- Init self-test (vrt a_nodata=none, INT1S).
- The worker checks GDAL 'Block=' against the master's model and returns native-width storage and its own rss/maxrss (plus rchar and a VmHWM reset on Linux).
- Graceful 'quit'; test hooks only with ANNOTATR_TEST_HOOKS=1.
- `R/backend.R`: - at_backend_register gains an optional additive capabilities_fn (capabilities stays a list) and the roxygen is updated.
- at_backend_list(), at_read_image() and at_backend_get() keep list semantics; capabilities_fn is evaluated in tryCatch, and a function is never stored in image meta.
- at_tile: for handle-less images with an available, verified source, look up the cache under the caller's identity before .reopen_image; on a reopen, store the tile and read stats under the caller's identity.
- Update the .handle_cache_clear comment.
- `R/io-window.R`: - Telemetry keys: native_block_bytes, native_os_read_bytes (accumulates only measured values), worker_starts, worker_requests.
- .read_telemetry_add aborts on unknown keys.
- .window_capabilities accepts additive fields; io stays in the documented vocabulary.
- at_image_capabilities evaluates capabilities_fn and documents engine, isolation and granularity.
- at_close_image wraps close_fn in tryCatch, warns on failure and always releases the handle; the docs describe the worker lifecycle.
- .memory_snapshot is removed in favour of .holds_pixel_arrays.
- `R/persistence.R`: No behaviour change. .holds_pixel_arrays becomes the only snapshot predicate. .reopen_image and .strip_persisted_handle work unchanged because the window handle holds no arrays and the reader reproduces dims, level_dims, n_bands, dtype, band_names, pixel_size and reader_contract.
- `R/zzz.R`: - tiff: the static list is the eager declaration plus capabilities_fn; available_fn = .tiff_backend_available.
- ometiff: TRUE/TRUE, io 'native', samples raw-scalar-v1.
- New .onUnload calls .gdal_worker_stop().
- `R/interop-capabilities.R`: .hsi_backend_caps:
- tiff: status supported when the engine or tiff is usable; window_read = engine usable; the engine is recorded.
- ometiff: window_read=TRUE, status still 'planned' until a qualified run is recorded.
It never loads terra. The capability digest change is documented.
- `R/hsi-meta.R`: Documentation only: for native engines file_bytes is the index-derived encoded block payload, and nodata is recorded but never applied for TIFF.
- `R/class-image.R`: Header comment: TIFF handles are windowed file references when the GDAL engine is used.
- `DESCRIPTION`: Suggests: add processx and ps (>= 1.9.0). terra and callr are already listed, and jsonlite is already in Imports. Imports are unchanged.
- `NAMESPACE, man/at_backend_register.Rd, man/at_backend_list.Rd, man/at_image_capabilities.Rd, man/at_close_image.Rd, man/at_read_stats.Rd`: Regenerate with roxygen for the capabilities_fn argument, the capability fields, the close lifecycle and the file_bytes semantics.
- `README.Rmd, README.md`: Supported-formats table: TIFF reads windows through terra and processx, with an eager fallback through tiff. Correct the sentence saying TIFF is decoded whole when opened. Re-knit.
- `vignettes/images-and-backends.Rmd`: - Backend table row for tiff: metadata-only open and GDAL block windows in an isolated worker; eager fallback; the annotatR.tiff_engine option; layout-bound cost.
- Compression whitelist; single-strip and planar caveats; worker memory and start cost.
- Telemetry keys; close and reopen behaviour; capabilities_fn migration note.
- The ometiff capability is declared but unqualified on this host.
- `NEWS.md`: - A34: planar-separate refusal in the eager and raster paths, and correct decoding through the engine.
- Windowed TIFF engine and the annotatR.tiff_engine option; new Suggests.
- Corrected ometiff capability declaration; changed interop capability digest and manifest fields (window_read, nodata) for TIFF.
- Budget preflight for the eager TIFF fallback: previously readable huge TIFFs now need annotatR.max_read_bytes raised.
- Closed-image caching and accounting; capabilities_fn.
- `tests/testthat/helper-tiff-writer.R`: New independent writer driven only by the TIFF specification; it shares no code with io-tiff-ifd.R, GDAL or libtiff.
- Classic and BigTIFF, II and MM; strips with arbitrary RowsPerStrip or tiles with partial edge tiles; contiguous or separate planes.
- Compression none, Deflate (a memCompress zlib stream) or PackBits; predictor 2 for integer samples.
- uint8, int8, uint16, int16, float32; optional GDAL_NODATA tag; sparse large files with literal tiles.
- Returns its IFD-structure bytes and per-block offsets and bytecounts as the layout oracle.
- `tests/testthat/helper-resources.R`: New measure_fresh_read() with the JIT disabled: the baseline is taken before at_read_image and the corrected metrics are recorded. Includes fixture builders for sparse ENVI, SpecCube and TIFF, and named capability skips.
- `tests/testthat/test-tiff-windows.R`: New tests: pixel matrix; codec whitelist; raw guards; environment sanitizing; truncation; budgets; telemetry; worker block check; message policy; source change; worker lifecycle (timeout, abort, interrupt, fork, quit, no detritus); isolation; init failure; eager fallback; persistence in both directions.
- `tests/testthat/test-window-resources.R`: New structural resource tests.
- Default lane (skip_on_cran): moderate sizes with a 256x256 window; on Linux also rchar and per-request VmHWM.
- Full lane behind ANNOTATR_RESOURCE_TESTS=true: large sparse files and JSON evidence through ANNOTATR_RESOURCE_EVIDENCE.
- `tests/testthat/test-windowed-readers.R`: - Positional third-party registration still yields NA capabilities.
- capabilities_fn is evaluated, and the list stays a list.
- A close_fn error warns and the handle is released.
- The second identical closed-image at_tile adds 0 bytes, and stats count under the caller's identity.
- Capability inventory rows.
- `tests/testthat/test-reader-correctness.R`: - A34 regressions: planar-separate is refused by the eager and raster paths and decoded exactly by the engine; a contiguous control decodes exactly.
- The A26 cases run under both engines through annotatR.tiff_engine, with skips split between engine and tiff availability.
- int32/uint32/float64 stay refused unless the user decides to extend the types.
- `tests/testthat/test-backend-tiff.R`: Existing multiplex, pyramid, AMBIGUOUS and writeTIFF cases run under both engines. Add expect_no_warning for multiplex tiles under the engine.
- `tests/testthat/test-tiff-process.R`: Eager fallback: a declared size over the budget fails before any annotatr-tiff- decoder directory is created. The existing callback-state cases still pass.
- `tests/qualification/window-resources.R`: Rewrite portably (macOS and Linux; Windows skips sparse files above 1 GiB) on top of helper-resources.R. Record versions, hardware and storage; emit JSON; keep the OME lane through ANNOTATR_EXTRA_LIBRARY.
- `planning/ADDITIONAL-FINDINGS.md, planning/IMPLEMENTATION.md, planning/VALIDATION.md, planning/ROADMAP.md, planning/evidence/<date>/t15/`: Record A34 with its failing-before evidence, the measurement method (JIT off, maxrss excess, Vcells, worker self-report, Linux rchar and VmHWM), the qualified configuration and the corrected OME archive numbers, and T15 status.

### Tests (with independent oracles)

- A34 regression (P1, first commit). A hand-written planar-separate uint16 cube gives TIFF_UNSUPPORTED through .tiff_raw_read and through the raster tiff branch (magick mocked absent). The same layout with PlanarConfiguration=1 decodes exactly. Under the engine, the planar file decodes exactly, full and windowed. Oracle: the formula cube value = 100*b + 10*y + x. Failing-before evidence: 57 of 60 zeros on main.
- Literal pixel matrix (test-tiff-windows.R). Fixtures come from helper-tiff-writer.R and cover {classic, BigTIFF} x {II, MM} x {strips with rps 1/3/full, 16x16 tiles with partial edges} x {contiguous, separate} x {none, Deflate+predictor 2 (integer types only), PackBits} x {uint8, int8, uint16, int16, float32 with NaN and +/-Inf} in a pairwise design. LZW comes only from tiff::writeTIFF (classic, II, one strip, contiguous, uint8/uint16). Checks: full level, windows crossing block edges, single corner pixels, band order c(3,1,3), every level of an anisotropic pyramid (level 1 sampled by y=2, x=4). Oracle: the formula, independent of annotatR and GDAL.
- Bundled independent fixtures under both engines. reference-{uint8,uint16,int16,float32,rgb}.tif must meet the unchanged A26 expectations. The same files plus int32/uint32/float64 are refused by the scan unless the type extension is decided. Oracle: the literal arrays in test-reader-correctness.R.
- Differential parity (supplementary). The engine equals the eager decode on example_multiplex.tif (3 levels, 4 samples) and on writeTIFF 1/3/4-channel 8/16-bit images and pyramids. Oracle: the eager reader, which is already checked against literal arrays.
- Metadata-only open. decoded_bytes == 0, native_window_calls == 0, worker_starts == 0, the handle holds no arrays, capabilities are metadata_only=TRUE and window_read=TRUE, and terra is not loaded in the main process. binary_bytes is at most the IFD-structure bytes the writer reports, and identical for two files that share a layout but differ in payload size. Oracles: the writer's layout record and loadedNamespaces().
- Block telemetry and model. For each window, native_block_bytes and at_read_stats()$file_bytes equal the sum of the writer-reported bytecounts of the intersecting blocks; chopped uncompressed strips count rows x row_bytes. The model's block dimensions equal terra::describe() 'Block=' on every layout in the matrix, including multi-strip uncompressed, tiny single-strip and planar files. A mocked mismatch between the model and GDAL gives BACKEND_CONTRACT. Oracles: the writer layout and GDAL's own block report.
- Raw guards and environment. An internal GDAL_NODATA tag returns the stored 0, not NA, and meta$nodata records it. A .aux.xml declaring NoData, Scale or Offset is ignored. A south-up .tfw does not flip rows. GDAL_METADATA scale and offset are ignored. Orientation is recorded but not applied. With GTIFF_IGNORE_READ_ERRORS=YES and CPL_DEBUG=ON set in the master's environment, a corrupted Deflate tile still fails with no array returned. Oracle: the literal arrays written to the files.
- Refusal codes (parity). Equal-size pages give TIFF_AMBIGUOUS. Pages with different sample counts give TIFF_AMBIGUOUS (mirrors test-backend-tiff.R 'mixed.tif'). A level with one larger dimension gives TIFF_AMBIGUOUS. Mixed dtype, palette, YCbCr, min-is-white, 1-bit, float16, mask IFDs, ZSTD/LZW-predictor3/WEBP/LERC/JPEG2000/old-JPEG, missing bytecounts and bytecount 0 all give TIFF_UNSUPPORTED. An IFD loop, an offset beyond EOF, too many directories and a truncated header error before any worker call. Oracle: hand-crafted bytes.
- Fail closed on block data. A tile truncated in the file gives PAYLOAD_SHORT from the master's index check, with worker_requests == 0. A corrupted Deflate stream gives an io error from the worker. Neither returns an array. Oracle: the explicit corruption in the fixture.
- Budget preflight. A single-strip Deflate 4096^2 uint16 file (32 MiB decoded) with annotatR.max_read_bytes = 16 MiB gives READ_BUDGET_EXCEEDED with worker_requests == 0. A tiled file of the same size reads the same 256x256 window under the same budget. Oracle: arithmetic on the declared layout.
- Message policy. at_tile on example_multiplex.tif under the engine raises no R warning (expect_no_warning), matching the tiff backend today. A GDAL error-class message during a read fails the request. Oracle: the warning condition stream.
- Source change. Appending bytes or touching mtime after open gives IMAGE_CHANGED for cached and uncached windows; at_relink_source() restores reads with identical pixels. Oracle: the original formula window.
- Worker lifecycle (ANNOTATR_TEST_HOOKS=1).
- With annotatR.tiff_timeout = 1, the 'sleep' op fails after about 1 s and the pid is gone.
- The 'abort' op fails with 'no image returned'.
- setTimeLimit interrupting a request leaves no desync: the next window returns correct pixels and worker_starts increments.
- mclapply children read correct windows, and the parent's worker pid is still alive afterwards.
- .gdal_worker_stop() leaves no process, no private dir and no Rtmp* directory created by the worker.
Oracles: ps::ps_is_running, the filesystem and the formula pixels.
- Isolation. In a fresh process, after open, windows, at_backend_list() and at_interop_capabilities(), 'terra' is not in the main process's loadedNamespaces(). The worker's loaded namespaces exclude magick and tiff even with R_DEFAULT_PACKAGES=magick set. Oracle: loadedNamespaces() in each process.
- Engine selection and init failure. annotatR.tiff_engine = 'eager' gives eager capabilities (io 'eager', window_read FALSE) and identical pixels. A mocked self-test failure gives CAPABILITY_UNAVAILABLE at the first window, after which the next open is eager and at_backend_list() shows FALSE/FALSE. A sparse declared 20000x20000 uint16 file gives READ_BUDGET_EXCEEDED in eager mode before any annotatr-tiff- decoder directory appears. Oracles: a tempdir listing plus the formula.
- Persistence in both directions. A project saved after an eager read reopens under the engine without relink, with identical dtype, band_names, level_dims, reader_contract and pixels. A project saved under the engine reopens with annotatR.tiff_engine = 'eager' the same way. The legacy-f69bf20 cases in test-persistence-legacy.R (array snapshot kept; revalidation) still pass. Oracles: the saved metadata plus formula pixels.
- Lifecycle (test-windowed-readers.R).
- A positional third-party registration yields NA capabilities, and at_backend_get(n)$capabilities stays a list.
- capabilities_fn is evaluated.
- A close_fn that errors produces a warning and the handle is released.
- Through a closed ENVI or TIFF image, a second identical at_tile adds 0 telemetry bytes, and at_read_stats(closed)$tiles counts the first read (on main: 149 bytes per call and 0 tiles).
Oracle: the telemetry counters.
- Capability inventory. at_backend_list() reports envi/tivita TRUE/TRUE; tiff TRUE/TRUE if and only if the engine is usable, else FALSE/FALSE; ometiff TRUE/TRUE; raster/cuvis FALSE/FALSE; third-party NA/NA. at_image_capabilities() and at_interop_capabilities('hsi') agree. ometiff status stays 'planned' with an empty qualified_with. Oracle: an explicit expected table.
- Resource tests, default lane (test-window-resources.R; skip_on_cran; needs callr and ps >= 1.9.0, plus terra and processx for TIFF; named skips otherwise). Fresh processes with the JIT disabled, 256x256 window, baseline before at_read_image. Cases: ENVI 512^2 vs 8192^2; SpecCube 512^2 vs 4096^2; tiled TIFF 1024^2 vs 8192^2 (sparse).
Assertions:
- Open and window bytes are identical across sizes.
- decoded_bytes = 8 x window elements.
- Header bytes <= 64 KiB; open decoded bytes are 0; the worker is not started at open.
- headroom0 <= 16 MiB.
- main_peak_excess <= 8 MiB at both sizes.
- Vcells delta <= 3 x window bytes + 4 MiB.
- Tiled worker_window_excess <= 16 MiB.
- On Linux, the worker's rchar delta is size-independent and <= block bytes + 1 MiB.
Oracles: OS getrusage maxrss, R gc Vcells and Linux /proc counters, all independent of annotatR telemetry; pixels equal the formula.
- Resource tests, full lane (ANNOTATR_RESOURCE_TESTS=true; large sparse files are skipped on Windows). ENVI 32768^2 (6 GiB), SpecCube 8192^2 (750 MiB) and tiled TIFF 32768^2 (2 GiB apparent), with the same assertions. Layout control: on a single-strip Deflate 8192^2 page, worker_window_excess is about the decoded strip (128 MiB). Negative control: eager 4096^2 gives a Vcells delta >= 128 MiB. Writes JSON evidence with elapsed times recorded but not asserted.
- OME lane (skip_if_not_installed for RBioFormats and xml2; blocked here because there is no Java). The same harness runs on window-resource-fixtures.py outputs at 512 and 16384, with an explicit OME bound that investigates the archived +50 MiB open and +29 MiB window difference. The existing native-subset fixture tests also run. Oracle: arrays written by tifffile.

### Acceptance

- Roadmap: 'Tests measure file bytes and memory from before at_read_image(), not after a full array already exists'.
Demonstrated by measure_fresh_read. It takes its baseline in a fresh callr child with the JIT disabled, before at_read_image: worker stopped, caches and telemetry reset, gc(reset=TRUE), and ps maxrss/rss recorded.
- File bytes: exact connection bytes for ENVI, TIVITA and the TIFF IFD scan; index-derived block bytes for TIFF windows; measured bytes via the worker's rchar on Linux (the default lane on the shared Linux CI).
- Memory: main maxrss excess over the baseline high-water, R-heap Vcells, and the worker's self-reported excess.
test-window-resources.R asserts these for envi, tivita and tiff, and for ometiff where RBioFormats exists.
- Roadmap: 'Fixed windows produce identical pixels to independent full-file fixtures'.
Demonstrated by the literal-formula matrix in test-tiff-windows.R. Fixtures come from the specification-only R writer and from libtiff's writer (tiff::writeTIFF) for LZW. The bundled tifffile-written reference-*.tif A26 cases run under both engines. Coverage: windows crossing block edges, every level of an anisotropic pyramid, duplicate and reordered bands, NaN/Inf, int8/int16 extremes and planar-separate files. The existing ENVI, TIVITA and OME window tests are unchanged.
- Roadmap: 'At least the specifically advertised large-data backends open and read windows without allocating full cubes'.
envi, tivita and tiff (GDAL engine, tiled or multi-strip layouts) pass the structural small-vs-large assertions on sparse 6 GiB, 750 MiB and 2 GiB-apparent files: identical bytes, decoded bytes equal to the window, and main/worker excess within tolerance. The eager negative control proves the harness is sensitive. Single-strip compressed and planar single-strip layouts are documented as layout-bound and protected by the pre-decode block budget. ometiff's window capability is declared as implemented but stays unqualified until the OME lane runs on a host with RBioFormats.
- Roadmap: 'Unsupported capabilities remain clearly identified'.
- The capability inventory test checks that at_backend_list, at_image_capabilities and at_interop_capabilities agree.
- raster, cuvis and the eager TIFF fallback report metadata_only=FALSE, window_read=FALSE and io='eager', with budget preflights.
- TIFF levels expose block dimensions, compression and granularity.
- The codec whitelist refuses lossy or unqualified encodings explicitly.
- An engine init failure is a classified CAPABILITY_UNAVAILABLE.
- Third-party backends stay NA.
- The vignette and README state the strategy and limits per backend.
- Roadmap body: 'qualify an appropriate TIFF/OME path with actual available dependencies and fixtures'.
The GDAL engine is qualified on the recorded configuration (macOS arm64, R 4.6.1, terra 1.9.50, GDAL 3.13.3, libtiff 4.7.x) plus the Linux CI lane. Evidence goes under planning/evidence/<date>/t15. The OME path is recorded as unverified on this host (no Java/RBioFormats).
- Roadmap body: 'Keep eager small-raster fallback explicit'.
The eager TIFF fallback, selected automatically or by annotatR.tiff_engine = 'eager', and the raster backend declare eager capabilities. Both run budget preflights before materializing arrays, and the measured peak multiplier is documented. Tests cover fallback selection and refusal before any decoder is spawned.
- Roadmap body: 'Add reopen/close lifecycle behavior without breaking third-party registered backends; document additive capability metadata and migration'.
- capabilities_fn is additive, and capabilities stays a list.
- close_fn is protected by tryCatch.
- Closed images are cached and counted under the caller's identity.
- Worker lifecycle: lazy start, quit on unload, restart after failure, fork guard.
- Positional third-party registration and legacy saved projects still pass.
- The vignette and NEWS carry migration notes, including the changed interop capability digest.
- VALIDATION.md performance table (T00 benchmark specification). A metadata open and a fixed 256x256 window are measured at two substantially different file sizes. Bytes read, peak memory and pixel equality are asserted; elapsed time is recorded. Repeating a window confirms cache hits and the absence of stale hits across source generations.

### Out of scope, blocked or needing a decision

- Blocked: OME-TIFF qualification on main. There is no Java runtime on this host (java_home finds none), and neither RBioFormats nor rJava is installed. The only evidence is the pre-port Linux run, with corrected numbers: open +220.6 vs +270.6 MiB and window +1.6 vs +30.9 MiB at 512^2 vs 16384^2. It needs a rerun, and an explanation of the size dependence, on a lane with RBioFormats. Writing the lane's code is not blocked.
- Blocked: CUVIS windowing. The SDK is unavailable and the only known API (cuvis_get_cube) returns the whole cube, so cuvis stays explicitly eager.
- [corrected] Not a user decision: the A34 refusal. Silent wrong pixels fall under the confirmed correctness-first priority, and refusing unqualified encodings is the existing rule. The fix is small because tiff::readTIFF(info=TRUE) already exposes planar.config. It lands as P1, before the engine work, and covers the raster branch too.
- Needs a user decision: extend TIFF sample types to int32/uint32/float64. GDAL decodes the reference fixtures exactly, including INT_MIN, 4294967295 and NaN/Inf (probe p3b.R), but test-reader-correctness.R and the vignette currently promise refusal. Default: keep parity and refuse. Accepting them would also make readability depend on the installation, since the engine could read them and the eager path could not.
- Needs a user decision: the default execution model. Option 1 is the isolated processx worker (recommended): about 200-220 MiB extra resident memory and a 2.2 s first start. Option 2 is in-process terra (9.6 ms per window), which survived the magick-first abort order on this host. Moving to option 2 should wait for T18a.
- Needs a user decision: the new Suggests processx and ps (>= 1.9.0). Both are already installed as callr dependencies. Without terra and processx, TIFF falls back to the eager reader.
- Needs a user decision: JPEG-compressed RGB TIFF. It is accepted today, but its values are defined by the decoder. The codec whitelist default refuses ZSTD/LZMA/WEBP/LERC/JPEG-XL/JPEG 2000 and predictor 3 until independent fixtures exist, and refuses GDAL sparse blocks (bytecount 0).
- Needs a user decision: Windows. The worker and the sparse-file tests are unqualified there. Either enable the engine and treat Windows CI failures as T18 blockers, or default annotatR.tiff_engine to 'eager' on Windows until T18 qualifies it.
- Out of scope (T16): downsampled and resampled previews. Until T16, widget-canvas.R:.preview_bands on a large non-pyramidal TIFF makes many full-resolution row-chunk reads through the worker: memory stays bounded but I/O is high. Also deferred to T16: retained-handle and queue limits, a reopened-handle LRU beyond caller-identity caching, streaming mask export, plot.R full-level reads, and TIFF mask import through the engine.
- Out of scope (T17): latency budgets and timing gates. T15 records elapsed times but asserts only bytes and memory. A per-call R allocation churn in at_tile on uncompiled code is likewise left to T17.
- Out of scope (T18a/T18): the native callback abort of the R tiff package, which still affects mask import (.read_mask_matrix) and the eager fallback; Windows-host qualification of the worker and the sparse files; GDAL older than 3.7 (for example Ubuntu 22.04 packages), where the engine reports itself unavailable.
- Out of scope: an OME reader built on GDAL+xml2 for when RBioFormats is missing. That is new reader logic and needs an explicit request.
- Not part of this step: the user's relayed request to delete the annotatr-roadmap folder. This review changed nothing in the repository. At review time no annotatr-roadmap or annotatR-roadmap folder exists under <CTTIR checkouts>, and git worktree list shows only the main worktree. The deletion therefore looks already done, or the folder is somewhere else; confirm the location with the user. The working tree now shows unrelated edits made outside this step (NEWS.md, planning records, comment wording in R/interop-*.R, an untracked test-export-contract.R).

### Risks

- The GDAL block model may not carry over to other builds. It depends on libtiff strip chopping (STRIPCHOP_DEFAULT, the 8192-byte strip size) and on how GDAL exposes blocks. Mitigation: the worker compares GDAL's actual Block= with the model and fails closed, and tests cross-check every layout.
- GDAL and terra versions differ across installations (Int8 and vrt a_nodata need GDAL 3.7 or later; Ubuntu 22.04 ships 3.4). The self-test runs only at the first window, because open never starts the worker, so an init failure surfaces late. Mitigation: a classified CAPABILITY_UNAVAILABLE that names the annotatR.tiff_engine option, and a session-cached fallback.
- Inherited GDAL configuration from the user's environment, such as GTIFF_IGNORE_READ_ERRORS=YES (probed) or GDAL_SKIP, can turn read errors into fabricated zeros. Mitigation: environment sanitizing, pinned options, and failing on error-class messages.
- Window cost depends on the file layout. A compressed single-strip page, or an uncompressed planar plane, decodes the whole plane in the worker. Users see READ_BUDGET_EXCEEDED rather than a slow full decode, and this must be documented.
- Worker cost and complexity: about 200-220 MiB resident memory that persists for the session, and a 2.2 s first start. Process management covers deadlines, kill, interrupts, fork guards, quit on unload, temp-dir hygiene for R CMD check, and log tails. Windows pipes and text mode still need qualifying in T18.
- Behaviour changes visible to partners and users:
- planar-separate files go from corrupted pixels to refused (eager) or correct (engine), so earlier analyses of such files will differ.
- TIFF capabilities, window_read and the nodata field change in manifests, and the interop capability digest (recorded by training.R and interop-manifest.R) changes and now depends on the installation.
- Huge TIFFs that used to open eagerly now need a larger budget.
- Code reading img$handle$levels for TIFF breaks; only backend-tiff.R does this today.
- Measurement limits. maxrss is a per-process high-water mark and cannot be reset (except VmHWM on Linux), so it is blind to allocations smaller than the baseline headroom. With the JIT on, the headroom ranged from 2.3 to 16.5 MiB and R-heap figures were dominated by compilation churn, which is why the harness disables the JIT. On macOS the worker must report its own memory. TIFF window bytes are measured only on Linux; elsewhere they are derived from the index. ps maxrss units must be checked against /proc VmHWM. Tolerances may need tuning on CI.
- Sparse fixtures are not sparse on NTFS, so large-file tests are skipped on Windows. Some CI filesystems apply disk quotas to apparent size.
- Path edge cases: a path containing '?' on a file with a NoData tag (vrt://) is refused; non-ASCII paths need enc2utf8; an ImageDescription larger than 1 MiB falls back to default band names, which forces a relink for projects saved by the eager reader.
- OME memory is size-dependent in the archived evidence (+50 MiB at open, +29 MiB after the window at 16384^2), so generic tolerances will fail until that is investigated.
- Effort above the roadmap range. With ENVI and TIVITA already done, the remaining TIFF, lifecycle and harness work is estimated at about 70 h. That exceeds the roadmap's 5-9 days for all of T15 once the completed parts are counted; re-estimate after P2.

### Depends on

- T01 (source identity and composite source signatures used for change detection and cache keys)
- T03 (source descriptors, .reopen_image, at_relink_source and fresh-process helpers used by the lifecycle, persistence and harness tests)
- T07 (raw-sample contracts and the independent reader fixtures; the A26/A27 expectations are reused as oracles)
- T09b (exact provenance keys; new meta and handle fields must not near-prefix required keys)
- T00 benchmark specification (VALIDATION.md performance table: metadata open and a fixed 256x256 window at two file sizes)
- Sequencing: P1 (A34) can land immediately; T15 must precede T18a (native TIFF callback containment) and T16/T17 (previews, queue memory, timing budgets)

## T16 — Bound preview, queue and export working memory (milestone M5; follow-up to findings O01/O02, plus the canvas display correction that T13 deferred to T16). This is the reviewed and corrected specification.

Estimated effort: 104 focused hours.

### Current state

Main is at 649cf49 (0.2.0 development). The working tree has uncommitted interop and planning-document edits from another workflow step; none of them touch T16 code. The review re-ran the draft's probes p10, p13, p14, p16 and p19. New probes r1–r6 are in <scratch> (r1_versions_tiffwriter.R, r2_giant_canvas.R, r3_tiled_tiff.R, r4_png_depth.R, r5_stretch_inf.R, r6_reopen_cache.R). [C] marks a corrected draft claim; [N] marks a gap the draft missed.

PREVIEWS

R/widget-canvas.R:.preview_bands()
- Picks the level with R/plot.R:.display_level() and uses stride s = ceiling(max(d)/max_dim).
- Reads every full-width row through at_tile() (R/backend.R) in chunks of max(s, floor(64e6/(8·W·nb))) rows, rounded down to a multiple of s, and keeps one row in s.
- The chunks go into the LRU tile cache (R/perf.R:.tile_cache_put, annotatR.cache_size = 512 MiB).
- The output holds every requested band. band_mean and wavelength_window_mean then reduce it with apply(mean) in .view_display_array: 2048²×100 bands = 3.36 GB, with no guard. Only the per-chunk .window_budget and max_tile_bytes checks apply.
- p2 (ENVI 8192×6000×3, max_dim 1024): reads the whole 295 MB file in 7–10 s, adds 1.0–1.3 GB to the heap and leaves 488 MB in the tile cache.

[C] The canvas does not fail on a 20000²×3 non-pyramidal image.
- r2 used a fake registered backend: .view_display_array() succeeds with 154 at_tile calls of at most 62.4 MB each, requesting all 20000 rows (2.4 GB for a uint16 ENVI file).
- Only R/plot.R:.image_display_df() fails, because it calls at_tile(img, level) for the whole level and all bands. It raises TILE_TOO_LARGE: 9.6e9 bytes against the 2 GiB annotatR.max_tile_bytes.

No preview cache.
- mod_canvas_server (R/app-modules.R) re-renders when rv$project, rv$tool, rv$selection, the active layer or label, or rv$view changes.
- Each render re-runs .image_data_uri_result(): read, stretch, magick PNG, base64. p6: a 2048² RGB noise image takes 3.5–4.7 s and gives a 33 MB URI.
- The widget keeps its decoded image only when the URI string is identical (inst/htmlwidgets/atcanvas.js renderValue, sourceChanged).

[N] Stretched previews are encoded as 16-bit-per-channel PNG, because magick keeps Q16 depth for double input.
- r4: the cube URI has bit depth 16.
- 512² noise is 1.58 MB at 16 bits versus 0.79 MB with depth = 8. The browser canvas is 8-bit.
- Native 8-bit images (tissue) are already 8-bit.

[C] .stretch01 takes 2–98% quantiles with na.rm = TRUE, which removes NA and NaN but keeps ±Inf.
- +Inf draws white; -Inf and NaN draw black.
- The whole channel is blanked only when non-finite samples reach the interpolated tail. r5: one Inf in a 4×4 preview blanks the channel. In 100×100, one Inf or 150 Inf does not blank it (the Inf pixel is 1.0); 300 Inf does.
- at_plot_image draws non-finite samples transparent.
- IMPLEMENTATION.md assigns this "RGB normalization error with nonfinite samples" to T16.

QUEUE

- R/app-state.R:.state_snapshot() stores the live project, handle included, into rv$session$projects and into the shared store (.app_store_put).
- R/batch.R:.materialize_project reopens only stripped handles.
- Eager backends keep double arrays (raster: handle$data; tiff: handle$levels). p4: retained handles grow by 15.4 MB per 800² RGB entry, RSS from 366 to 735 MB over 24 entries.
- The same retention happens in:
  - rv$recovery_queue (.state_replace)
  - the hub: .cmd_goto, .hub_project, .hub_push_from_app. With a hub, apply_hub sets rv$session to hub$session, so both copies share handles.
  - at_batch_apply
- History: each stack is capped at 50, but rv$history keeps one stack per edited entry. Snapshots hold layers only, so its memory is small.
- at_close_image (R/io-window.R) mints a new identity and leaves tiles in the cache. The vignette documents this as intended: "Closing does not purge the shared tile cache".

[N] Released handles are re-decoded on every read.
- at_tile reopens a handle-less image inside every call and never returns the reopened handle. It then caches the tile under that call's fresh identity.
- r6: three identical at_tile calls on a closed cube leave three cache entries with three identities. A closed raster re-decodes on each call.
- at_extract and at_extract_pixels (R/extract.R) call at_tile per ROI, and the training export calls it per tile. So releasing an eager handle means one decode per ROI or tile; for TIFF, each decode is an isolated subprocess.

[N] Some snapshots cannot be reopened.
- R/persistence.R:.reopen_image refuses a reopen when backend, dtype, band_names, wavelengths, units, pixel size or reader contract differ from what the reader returns.
- at_example_image('multiplex') sets band_names after reading. Releasing such a snapshot would leave the entry "unresolved".

[N] .holds_pixel_arrays (R/persistence.R) and its duplicate .memory_snapshot (R/io-window.R) are structural checks only.
- Built-in tile functions index [y, x, band]: handle$data for raster, envi, tivita and cuvis; handle$levels for tiff and non-windowed ometiff.
- A registered third-party backend may store arrays in another layout.

[N] Saving can materialise pixels. .save_checkpoint reloads NULL entries that have a project_path through at_load_project(), which materialises pixels. The result becomes rv$session after a Save.

MASKS AND EXPORT

- at_mask (R/mask.R) has no guard. p7: the peak is 5.4–8.5× the 4-byte output.
- Only .cmd_mask_preview has a budget: annotatR.control_mask_max_pixels = 4096².
- .current_mask builds full level-0 masks for the overlay and for the Summary preview and stats. The Summary page renders only while it is visible.
- These paths materialise full matrices:
  - at_write_mask
  - at_write_masks (per = 'roi' builds one full-size mask per ROI; the receipt n_px is computed from the matrix)
  - at_write_npy
  - .export_project_file
  - the training export (plus one full-size .cover per ROI)
  - [N] R/interop-handoff.R masks (at_export_qupflowr and the control 'export' command) and .mask_record
- r1: tiff::writeTIFF in tiff 0.1.12 defaults to LZW and writes one strip, so the draft's byte-identity note is right.

.export_bundle
- Stages files as hidden '.export-stage-*<ext>' and publishes the mask before its sidecar.
- [N] Its publication tryCatch handles errors only. An interrupt between the backup and publish renames leaves the destination missing, with the prior files only in hidden '.export-previous-*' copies.
- [N] .export_outcome turns every error into a receipt row, so a future at_cancelled_error would not stop a batch.

[N] Read-back limits.
- at_read_npy (via .binary_layout with eager = TRUE) needs count×8 ≤ annotatR.max_read_bytes (1 GiB, i.e. 2^27 px).
- TIFF read-back decodes doubles in a subprocess.

There is no streamed export.

PROBE CONFIRMATIONS

- r3: readTIFF(as.is = TRUE) kills a callr child on a GDAL-tiled TIFF; as.is = FALSE works.
- r3: terra's default INT2U writeStart/writeValues declares NoData 65535, and 65535 reads back as NA. With NAflag = NA it still writes NoData nan.
- p10: ALL_TOUCHED rasterisation depends on the extent. With 20-row blocks, 4/20 integer-vertex polygons differ; with 20-column blocks 8/20; changing only the height, 1/20. Same for stars and terra.
- p13: 32/32 windowed configurations match at_mask.
- p14: 120/120 lattices match; a 20000×15000 overlay takes 0.04 s and +8.2 MB.
- p16: the pure-R TIFF and BigTIFF writer, with or without deflate, decodes exactly through the isolated libtiff reader and through GDAL.
- p19: magick encodes 2048² noise in 3.25 s as RGBA versus 0.86 s as RGB.
- ps 1.9.3 works inside callr children. On macOS, RSS does not fall after gc.

BUILDING BLOCKS ON MAIN

- Exact centre membership with a global origin: .cover / .cover_polygon / .cover_shortcircuit / .centre_range. It is used windowed by R/extract.R and was proven for row blocks by p13.
- ENVI and TIVITA window readers: .envi_read_distinct and .tivita_read_window, with .window_read_raw telemetry.
- Staged bundles; isolated libtiff decoding (.tiff_read_isolated).
- The vignette sentence "Preview, queue and export memory require their own limits".

STILL MISSING

- Bounded decimated reads and a preview cache.
- Retention without re-decode storms.
- An at_mask guard.
- A streamed, exact, cancellation-safe writer.
- Documented limits.

### Design

This design corrects the draft. The draft's probes are in scope/; the review probes are in scope/t16rev/. The repository was not modified.

D1. BOUNDED DECIMATED PREVIEWS (new R/preview.R; changes in R/widget-canvas.R, R/plot.R, R/backend-envi.R, R/backend-tivita.R, R/backend.R)

.preview_plan(img, max_dim, level = NULL)
- Returns level (.display_level unless given), d = at_dims(img, level), s = max(1, ceiling(max(d)/max_dim)), ys = seq(1, d[2], s) and xs = seq(1, d[1], s).
- length(ys) and length(xs) are at most max_dim by construction.
- This is the same top-left sampling rule as at_mask_preview.

.image_lattice(img, level, ys, xs, bands, budget = annotatR.preview_chunk_bytes, default 32 MiB)
- Returns exactly at_tile(img, level)[ys, xs, bands] and never touches the tile cache.
- Steps:
  1. Validate through .tile_request(), factored out of at_tile with unchanged behaviour. Check the output with .window_budget(length(xs), length(ys), nb).
  2. img <- .reopen_image(img, require_pixels = TRUE), once per call.
  3. Dispatch through an internal .lattice_readers map, keyed by backend name and accepted only when identical(at_backend_get(name)$tile_fn, <the built-in function>):
     - (a) Built-in eager arrays. Index exactly the array the tile_fn indexes: handle$data for raster, envi, tivita and cuvis; handle$levels[[level+1]] for tiff and non-windowed ometiff. Cost is O(output).
     - (b) Built-in windowed readers: .envi_read_lattice for envi and TIVITA ENVI exports; .tivita_read_lattice for SpecCube.
       - With s = 1, or contiguous kept rows, delegate to the existing contiguous readers (.envi_read_distinct, .tivita_read_window) in row chunks within the budget.
       - With s > 1, per kept row: BSQ reads the span [min(xs), max(xs)] once per band.
       - BIL reads span × nb, or the whole row of B × span when 2·nb ≥ B (the .envi_read_distinct coalescing rule).
       - BIP reads span × B.
       - SpecCube reads one contiguous y-span × B per kept column.
       - Bytes read: BSQ/BIL length(ys) × span × nb × size; BIP length(ys) × span × B × size; SpecCube length(xs) × yspan × B × vb.
     - (c) Everything else (third-party backends, windowed OME): call b$tile_fn() per kept row over column chunks within the budget, check the shape as at_tile does, then subset xs.
  4. Record .read_stats_add per backend call.
  5. For non-snapshots, require .source_status == 'available' after reading, else raise IMAGE_CHANGED.
- p3: BSQ, BIL and BIP all equal the writeBin oracle; 36.8 MB is read instead of 295 MB, in 0.23–0.31 s instead of 7–10 s, with nothing cached.

Callers
- .preview_read() replaces .preview_bands(), which stays as an alias.
- .view_display_array(): band_mean and wavelength_window_mean accumulate per-pixel sums inside each row-group read. This is one pass over the file, never one re-read per band group, which would multiply BIP/BIL/SpecCube I/O. Memory is [ny, nx] sums plus one row group. NA, NaN and Inf propagate as mean() does.
- One .display_stretch(m) replaces .stretch01:
  - quantiles over finite samples only;
  - non-finite samples become NA;
  - a constant channel gives 0 for its finite samples;
  - the native path (.native01) keeps NA;
  - zero-denominator ratio and normalized_difference pixels stay NA.
- .encode_display_png(arr):
  - RGB through magick when there is no NA; RGBA with alpha 0 wherever any channel is NA.
  - Recommended: image_write(depth = 8), which halves the URI and matches the 8-bit canvas (r4). This is a user decision. Without it, all-finite previews stay byte-identical to today.
- R/plot.R:.image_display_df(): resolve the rgb bands or the single band first, then read only those bands with .image_lattice() at fac = ceiling(max(d)/max_dim). Grid, stretch and NA handling are unchanged. Invalid band indices now fail through the shared validation, so the error message changes.
- Option annotatR.canvas_max_dim: default 2048, allowed 64..8192, used by at_tile_source() and .image_data_uri().

D2. PREVIEW CACHE (R/preview.R)

Storage
- Package environment .preview_cache with store, LRU order and a byte total.
- Limits: annotatR.preview_cache_bytes (default 128 MiB; 0 disables the cache) and annotatR.preview_cache_entries (default 16).

Key: sha256 of identity, level, stride, spec$operation, spec$bands, spec$params, natural, max_dim, img$dtype, algorithm 'annotatR-display-v2' and the encoder tag.
- With a read_generation, identity = list(cache_identity, read_generation, descriptor backend, options_identity, signature, files). The cache hit happens before any read.
- Without one, identity is the sha256 of the lattice samples.

Use
- The magick availability check stays before the lookup, so T11 semantics do not change. The lookup sits in .image_data_uri_result, below the .image_data_uri seam.
- A hit is served only when the image holds pixel arrays, has no descriptor, or .source_status == 'available'.
- Failures are never cached. A view-fallback result is cached under the default view's key.
- at_close_image() and automatic release (D3) call .preview_cache_drop(identity) and .tile_cache_drop(identity). For the latter, the tile cache gains a key→identity map.
- clear_image_caches() also clears the preview cache. Tests that mock the encoder disable the cache.

[N] at_tile no longer calls .tile_cache_put when it had to reopen the handle inside the call (the reopened cache_identity differs from the caller's). This stops dead entries piling up (r6).

D3. BOUNDED RETENTION (new R/retention.R; changes in R/app-state.R, R/control-*.R, R/app-control-sync.R, R/batch.R, R/training.R, R/extract.R, R/persistence.R)

Options
- annotatR.app_retained_images: default 3; Inf disables eviction; the live entry is always kept.
- annotatR.app_retained_bytes: default 512 MiB.
- annotatR.app_history_entries: default 10.
- annotatR.app_history_depth: default 50; initialises rv$history_limit.

Helpers
- .handle_releasable(img) requires all of:
  - the image holds pixel arrays;
  - .strip_persisted_handle(img);
  - .source_status == 'available';
  - [N] the digest of the reopen-checked fields (dims, n_bands, level_dims, backend, dtype, band_names, wavelengths, wavelength_unit, pixel_size, pixel_unit, reader_contract) still equals the digest recorded when at_read_image() or .reopen_image() created the handle. If no digest was recorded, the image is pinned.
- [N] .release_snapshot(img):
  - drops the handle reference;
  - mints a new cache_identity and clears read_generation;
  - drops the old identity's tile and preview cache entries.
  - It does NOT call close_fn: other live copies (shared store, hub, other tabs) may share the handle. at_close_image stays the explicit API that calls close_fn.
- .queue_release_handles(session, keep_ids, max_images, max_bytes): walks entries in MRU order, keeps handles while the count and object.size budgets both hold, and releases the rest.
- .queue_memory_report(session): per entry holds_pixels, releasable and bytes.

App
- rv$mru is updated in .state_adopt.
- .state_retain(rv) runs at the end of .state_load, .state_replace, .state_restore_queue and [N] .state_save. It:
  - releases handles in rv$session and in .app_live_store;
  - releases every releasable handle in rv$recovery_queue (session projects and project image);
  - prunes rv$history to tail(rv$mru, app_history_entries). A pruned entry's undo stack is empty; its dirty flag and layers are kept.
- Restoring a queue reopens old$project$image before .state_adopt.
- [N] .save_checkpoint reloads NULL entries without materialising pixels, through an internal restore with materialize = FALSE.

Hub
- hub$mru and .hub_retain(hub) are called in .cmd_goto, .hub_project and .hub_push_from_app. Because the app copies hub$session, both sides must release.

Batch and other consumers
- [C] at_batch_apply restores the handle state of its input. It releases only handles it materialised from stripped inputs; entries that already held pixels keep them. Peak memory is one image.
- [N] at_extract, at_extract_spectrum and at_extract_pixels reopen once per call.
- The training export reopens once per entry, and only when include_images is TRUE.

Evidence: p5 (MRU-2) keeps retained handles at 15.4 MB, the heap flat at 148 MB and RSS at 344–356 MB over 80 steps.

D4. AT_MASK GUARD (R/mask.R)

- .mask_max_pixels() reads annotatR.max_mask_pixels: default 2^27, a user decision; must be positive and finite; capped at .Machine$integer.max.
- The check runs after .resolve_mask_dims and before any matrix() call. at_mask_stack checks pixels × layers.
- The error: .at_abort(class = 'limit', code = 'MASK_TOO_LARGE', details = list(width, height, pixels, limit_pixels)), with hints to use at_write_mask_stream(), a coarser level, or the option.
- Callers that inherit the guard:
  - at_write_masks and at_export_all, which stream under stream = 'auto' (D7);
  - the app (D7);
  - the training export;
  - [N] at_export_qupflowr and the control 'export' command, which are guarded but not streamed.
- The control mask.preview command keeps its own budget.
- Documentation states the measured transient peak of about 5–9×.

D5. WINDOWED EXACT RENDERING (R/mask.R)

.mask_plan(x, type, layer, label, level, background, touches, dims, values, overlap, engine, image, call)
- This is the front half of at_mask. It returns:
  - z-sorted entries and per-entry codes;
  - the code map, dims and background;
  - .legend_skeleton() (.build_legend without counts, including absent mapped classes and their order);
  - the source identity;
  - per-entry extents from .bbox_range;
  - exact = !touches && every geometry is POLYGON, MULTIPOLYGON, POINT or MULTIPOINT.
- [N] .mask_validate_metadata is split into structural checks, which the plan runs, and pixel checks, which construction guarantees.
- at_mask keeps its reviewed full-grid path.

[C] The T04-reviewed .centre_range, .cover_polygon and .cover_shortcircuit are NOT modified.
- Row blocks use .cover(geom, dims, touches = FALSE, origin), exactly as extract.R and p13 do.
- Lattice previews use a new .cover_lattice(geom, n_cols, n_rows, s) (the p14 prototype, origin 0) and lattice-filtered containing cells for points. It is tested differentially against .cover_polygon sampled at the lattice.

Renderer
- .apply_overlap() is factored out of .rasterize_per_roi.
- .mask_render_window(plan, rows): renders each entry over extent ∩ block, applies the overlap policy pixel by pixel in plan order (overlap = 'error' aborts like at_mask), and requires plan$exact.
- .mask_preview_lattice(..., max_dim): returns the at_mask_preview result (parent_grid, dims, stride, recounted legend, logical for binary). When s = 1 it returns the full mask. Non-exact plans fall back to at_mask_preview(at_mask()), under the guard.

Evidence
- p13: 32/32 configurations identical to at_mask.
- p14: 120/120 lattices identical.
- p8–p10: touches = TRUE and line rasterisation cannot be streamed exactly.

D6. STREAMED EXPORT (new exported function in R/mask-stream.R)

Signature
- at_write_mask_stream(x, path, format = c('tiff', 'npy'), type, layer, label, level, background, values, overlap, bits = c(16L, 8L), dtype = c('int32', 'uint8', 'int16'), compress = TRUE, legend = TRUE, overwrite = FALSE, block_bytes = annotatR.mask_block_bytes (default 8 MiB), progress = NULL, image, dims, call)
- Returns the path invisibly. touches, engine and transpose are not offered: rows are y and storage axes are always 'yx'.

Blocks
- Block rows = max(1, min(H, floor(block_bytes / (4W)))).
- Codes and background are range-checked against bits or dtype from the plan, before any file exists. This is stricter than at_write_mask's check of present values and is documented.
- Counts are accumulated exactly as .mask_recount, as doubles, plus a non-background pixel count for the at_write_masks receipt n_px.

.tiff_stream_sink (pure R)
- Little-endian baseline TIFF; BigTIFF when 16 + W·H·bytes plus the IFD is at least 2^32.
- One IFD with sorted tags: 256, 257, 258 (8 or 16), 259 (8 = zlib via memCompress('gzip'), or 1), 262 = 1, 273, 277 = 1, 278 = block rows, 279, 284 = 1, 339 = 1.
- Strips only; every strip except the last is full.
- No geo, NoData, date or software tags, so output is deterministic.
- Offsets are tracked arithmetically. The header region stays zero until commit, which closes the write connection, reopens the file 'r+b', patches offset 0 and verifies the first bytes.

.npy_stream_sink
- NPY 1.0, fortran_order False, rows written in C order; the header stays zero until commit.
- .npy_header_bytes() is shared with .npy_write_matrix, which stays Fortran order.

Sidecar
- .mask_legend_payload() is factored out of .write_legend_json. The keys are mask_metadata, storage (NPY: axes 'yx', shape [H, W]), annotatR_version (not 'version'), created, mask_type, level, dims, source_project and legend.
- A top-level export object records {rendering, block_rows, format, compression}. .check_provenance_keys only rejects duplicate keys, so the extra key is accepted.

Publication [C]
- .export_bundle publishes secondary files (sidecars) before the primary output for every bundle.
- It stages every member as '.export-stage-*.partial'. Writers are extension-agnostic: only readers call tools::file_ext.
- It restores backups when publication is interrupted, using an on.exit completion flag instead of an error-only tryCatch.
- None of this adds API arguments.

Cancellation
- progress(rows_done, rows_total) returning FALSE raises .at_abort(class = 'cancelled', code = 'EXPORT_CANCELLED'). Interrupts unwind through on.exit.
- [N] .export_outcome re-signals at_cancelled_error and interrupts, so a cancelled batch stops instead of becoming one error row.
- After SIGKILL, only hidden .partial stage files with zero headers remain.

Non-exact plans
- Within .mask_max_pixels(): render with at_mask(), stream the matrix through the same sink and record rendering 'in-memory'.
- Otherwise: STREAMING_UNSUPPORTED (class capability), listing ROI ids and geometry types, before any file exists.

D7. INTEGRATION

stream = c('auto', 'never', 'always') is added to at_write_masks, at_export_all, .export_session_items and .export_project_file, all routed through .write_project_mask:
- 'auto' keeps today's in-memory bytes within the limit and streams a 16-bit TIFF above it;
- 'never' produces a MASK_TOO_LARGE receipt row;
- 'always' streams.

App
- send_overlay and the Summary preview use .mask_preview_lattice at max_dim 1024 and 400.
- [C] Stats use the bounded streamed count pass for exact plans of any size. at_mask_stats is used only for non-exact plans within the limit.
- The overlay and preview show the MASK_TOO_LARGE reason instead of silently dropping.
- 'Export this mask' goes through .write_project_mask.
- exportTestValues gains retained_images.

The control mask.preview command keeps its column-major sha256 contract unchanged.

D8. DOCUMENTATION

- A new ?annotatR-options page listing the new and the existing options: cache_size, max_tile_bytes, max_read_bytes, max_npy_header_bytes, tiff_timeout, control_mask_max_pixels and control_hash_max_bytes.
- images-and-backends, 'Memory discipline':
  - preview lattice bounds and the preview cache;
  - [C] replace 'Closing does not purge the shared tile cache';
  - automatic release does not call close_fn.
- masks: a 'Large masks' section covering the guard, streaming formats, the exactness contract, unsupported touches and lines with the reason, cancellation, and read-back limits (at_read_npy needs count×8 ≤ max_read_bytes).
- shiny-workflow:
  - retention and history bounds;
  - a source changed after eviction shows IMAGE_CHANGED on revisit while annotations are kept.
- NEWS behaviour changes:
  - transparent non-finite and zero-denominator canvas pixels;
  - the at_mask limit;
  - closing purges caches;
  - sidecar-first publication;
  - at_batch_apply handle restoration;
  - streamed mask_tiff above the limit;
  - 8-bit canvas PNG, if adopted.
- _pkgdown.yml entries for the new function and the options page.

### Files

- `R/preview.R`: New file:
- .preview_plan, .image_lattice, the .lattice_readers map keyed by backend name plus identical() built-in tile_fn check, .preview_read, .canvas_max_dim, .preview_chunk_bytes
- Preview cache: .preview_cache env, .preview_key (identity + display settings + dtype), get/put/drop/clear/stats
- .display_stretch, .encode_display_png (RGBA only when NA; optional depth = 8)
- `R/widget-canvas.R`: - .preview_bands becomes an alias of .preview_read.
- .stretch01 is replaced by .display_stretch.
- .view_display_array uses lattice reads and accumulates band means within row-group reads.
- .image_data_uri_result: magick check first, then cache lookup, then encode; the .image_data_uri seam is unchanged.
- at_tile_source uses annotatR.canvas_max_dim; docs updated.
- `R/plot.R`: .image_display_df resolves the needed bands first and reads them via .image_lattice; output is identical for valid inputs.
- `R/backend-envi.R`: Add .envi_read_lattice:
- s = 1 delegates to .envi_read_distinct in budgeted row chunks;
- s > 1 reads per kept row with the BSQ/BIL/BIP spans and BIL coalescing described in D1;
- telemetry via .window_read_raw.
- `R/backend-tivita.R`: Add .tivita_read_lattice: one contiguous y-span × B per kept column. ENVI exports use .envi_read_lattice.
- `R/backend.R`: - Factor .tile_request() out of at_tile with unchanged behaviour.
- at_tile skips .tile_cache_put when it reopened the handle inside the call.
- at_read_image records the reopen-field digest.
- `R/perf.R`: Tile cache gains a key→identity map and .tile_cache_drop(identity). .centre_range and .cover_shortcircuit are NOT changed.
- `R/io-window.R`: at_close_image purges tile and preview cache entries of the released identity; docs updated.
- `R/persistence.R`: - .reopen_image records the reopen-field digest on success.
- .save_checkpoint reloads NULL entries without materialising pixels.
- `R/retention.R`: New file:
- .handle_releasable (adds the digest check)
- .release_snapshot (no close_fn)
- .queue_release_handles, .queue_memory_report
- option accessors .retained_images (Inf allowed), .retained_bytes, .history_entries, .history_depth
- `R/app-state.R`: - rv$mru, .state_touch (from .state_adopt) and .state_retain.
- .state_retain is called from .state_load, .state_replace (also releases recovery-queue handles), .state_restore_queue (reopens before adopting) and .state_save.
- history_limit comes from the option.
- `R/app-modules.R`: - Overlay and Summary preview use .mask_preview_lattice and show the MASK_TOO_LARGE reason.
- Stats use the bounded count pass for exact plans.
- 'Export this mask' goes through .write_project_mask.
- `R/app-builder.R`: Document rv$mru; exportTestValues adds retained_images.
- `R/control-state.R`: hub$mru, .hub_retain; .hub_project calls it.
- `R/control-commands.R`: .cmd_goto calls .hub_retain after the navigation commits.
- `R/app-control-sync.R`: .hub_push_from_app calls .hub_retain.
- `R/batch.R`: - at_batch_apply restores input handle state (releases only handles it materialised).
- at_export_all and .export_session_items gain stream.
- `R/extract.R`: at_extract, at_extract_spectrum and at_extract_pixels reopen the image once per call, so at_tile does not re-decode per ROI.
- `R/training.R`: Reopen each entry's image once, only when include_images = TRUE.
- `R/mask.R`: - Add .mask_plan, .legend_skeleton, .mask_max_pixels and the guard in at_mask and at_mask_stack.
- Add .apply_overlap, .mask_render_window (uses the existing .cover origin path), .cover_lattice (new; reviewed membership functions untouched), .mask_preview_lattice.
- Split structural and pixel checks out of .mask_validate_metadata (in R/mask-metadata.R).
- `R/mask-metadata.R`: Expose a matrix-free structural metadata validator, reused by .mask_plan and the stream sidecar.
- `R/mask-stream.R`: New file, exported at_write_mask_stream. Also:
- .tiff_stream_sink (TIFF/BigTIFF strips, header committed last via r+b patch)
- .npy_stream_sink (C order)
- .mask_stream (block loop, counts, non-background count, progress and cancellation)
- .mask_stream_counts
- .write_project_mask (auto/never/always)
- `R/mask-io.R`: - .write_legend_json refactored onto .mask_legend_payload (keeps annotatR_version; optional export block; existing output unchanged).
- at_write_masks gains stream; receipt n_px comes from stream counts when streaming.
- `R/io-npy.R`: Factor .npy_header_bytes(descr, shape, fortran), shared by both writers.
- `R/export-policy.R`: - .export_bundle: secondary files are published before the primary output; stages are named '.export-stage-*.partial'; backups are restored on interrupted publication (on.exit flag).
- .export_outcome re-signals at_cancelled_error and interrupts.
- .export_project_file takes stream and routes mask_tiff through .write_project_mask.
- `R/interop-handoff.R`: No streaming. Document that handoff masks are subject to MASK_TOO_LARGE, and pass the guard's error through to the control 'export' response.
- `R/annotatR-options.R`: New documentation-only file with @name annotatR-options listing every option, its default and meaning.
- `NAMESPACE`: export(at_write_mask_stream), via roxygen.
- `man/`: Regenerate Rd files:
- new: at_write_mask_stream.Rd, annotatR-options.Rd
- updated: at_mask, at_mask_stack, at_write_masks, at_export_all, at_close_image, at_tile_source, at_plot_image, at_batch_apply, at_extract*
- `DESCRIPTION`: Add ps to Suggests only if a testthat file uses it. tests/qualification is in .Rbuildignore. callr and png are already in Suggests.
- `tests/testthat/helper-annotatR.R`: - clear_image_caches() also clears the preview cache.
- New helpers: patterned_envi(W, H, B, interleave) and patterned_speccube() using writeBin with value 100b + 10y + x; sparse_envi(); queue_session(n, w, h) writing distinct small TIFFs (keeps the generating arrays as oracle); register_fake_backend() for third-party fallback tests.
- `tests/testthat/test-preview-bounds.R`: New:
- lattice values and dims (memory, ENVI BSQ/BIL/BIP, SpecCube, cuvis hand-built, fake third-party backend)
- bytes-read formulas per interleave
- no tile-cache fill
- giant cube canvas/plot
- plot equivalence
- one-pass band means
- non-finite display
- no caching of reopened tiles
- `tests/testthat/test-preview-cache.R`: New: hit, miss and invalidation (view, bands, max_dim, close, relink, source change, in-place mutation of hand-built images); limits; disabling.
- `tests/testthat/test-queue-retention.R`: New:
- full-server handle cap, reopen exactness, history pruning
- pinned and modified-metadata images
- source changed after eviction
- heap stabilisation
- recovery queue, hub, Save path
- at_batch_apply state restoration
- extraction reopen-once
- close purges caches
- `tests/testthat/test-mask-guard.R`: New: limit raised before allocation, at_mask_stack, option validation, stream = 'never' receipts, handoff surfaces MASK_TOO_LARGE.
- `tests/testthat/test-mask-stream.R`: New:
- hand-computed literals
- differential identity incl. overlap = 'error'
- streamed vs at_write_mask decoded equality, sidecar equality
- lattice previews; refusals and range checks
- 8-bit positive decode, determinism, BigTIFF, bounded memory
- `tests/testthat/test-mask-stream-cancel.R`: New:
- progress cancel and interrupt
- injected sink-commit and rename failures
- sidecar-first publication order
- interrupt during publication
- batch cancellation stops at_export_all
- callr hard kill
- `tests/testthat/test-widget-canvas.R`: - Extend the 8-bit/stretch test with the non-finite cases.
- The W3 'decoder exploded' test sets options(annotatR.preview_cache_bytes = 0), so a cache hit cannot mask the mocked failure.
- `tests/testthat/test-plot.R`: Lattice-based .image_display_df is identical() to a test-local copy of the old full-read algorithm (valid inputs; tissue, cube, multiplex levels, hand-built, fake backend).
- `tests/qualification/memory-bounds.R`: New fresh-process callr script with ps RSS and gc trajectories:
- 100-entry navigation
- 20000² sparse ENVI preview
- 12000×9000 streamed export vs at_mask
Writes result files and structural pass/fail for T17.
- `tests/qualification/npy-stream-check.py`: New stdlib-only independent NPY reader (shape, dtype, order, sha256 of C-order values). Run it with python3 -I.
- `vignettes/images-and-backends.Rmd`: Update 'Memory discipline':
- lattice bounds and the preview cache
- replace the 'Closing does not purge the shared tile cache' sentence
- automatic release semantics
- options table
- `vignettes/masks.Rmd`: New 'Large masks' section: guard, at_write_mask_stream formats and exactness contract, unsupported touches/lines with the reason, cancellation, publication order, read-back limits.
- `vignettes/shiny-workflow.Rmd`: Retention and history bounds, revisit cost, changed-source behaviour after eviction.
- `NEWS.md`: T16 entries: new function and options, plus the behaviour changes listed in D8. NEWS.md currently has uncommitted edits from another step; merge with them.
- `_pkgdown.yml`: Add at_write_mask_stream under Masks and annotatR-options under the reference 'Concepts' section.

### Tests (with independent oracles)

- Lattice values and limits:
- For (W, H) in {(1013,797), (2049,17), (5,4000)} and max_dim in {64, 100, 1024}, over: in-memory arrays, patterned ENVI BSQ/BIL/BIP, a patterned SpecCube, a hand-built cuvis image, and a registered fake third-party backend.
- Preview dims equal ceiling(d/s) and are at most max_dim.
- Values equal 100b + 10y + x at (ys, xs).
- Oracle: the closed formula on fixtures written independently with writeBin.
- Bytes read (skip_on_cran):
- Sparse 8192×6000×3 uint16 cube, telemetry reset after at_read_image so the header read is excluded.
- binary_bytes equals length(ys)·span·nb·2 for BSQ and BIL, and length(ys)·span·B·2 for BIP (checked with a 10-band BIP cube and 3 selected bands).
- SpecCube: length(xs)·yspan·B·vb.
- .tile_cache$bytes stays 0.
- gc max-used delta < 4 × output bytes + 32 MiB.
- Oracle: layout arithmetic.
- Giant non-pyramidal image (skip_on_cran, skip_on_os('windows')), sparse 20000²×3 ENVI:
- at_plot_image(img, max_dim = 256) returns a ggplot (it previously raised TILE_TOO_LARGE) and .image_display_df has at most 256² rows. ggplot_build is not run.
- The canvas .view_display_array previously succeeded but requested all 20000 rows (r2). It now requests at most ceiling(20000/s) rows (counted with a fake backend, or ENVI binary_bytes) and returns dims ≤ 2048.
- Oracle: dimension and row arithmetic.
- Plot equivalence: the new .image_display_df is identical() to a test-local copy of the old algorithm (full at_tile, then subsample) for tissue, cube, every multiplex level, hand-built and fake-backend images, with default, rgb and bands arguments and max_dim 7, 100 and 1024.
- One-pass band means:
- On a patterned 512×512×40 BSQ cube and a 10-band BIP cube, band_mean equals apply(full[ys, xs, ], c(1,2), mean) from an independent full at_tile read (expect_equal, tolerance 1e-12).
- The BIP file is read once: binary_bytes equals a single pass.
- gc max-used delta stays below the [ny, nx, nb] double allocation.
- Non-finite canvas display:
- A 4×4×3 image and a 100×100×3 image with one Inf (which previously drew white, r5) and with NaN, -Inf and NA are encoded, then decoded with png::readPNG.
- Alpha is 0 exactly at the non-finite pixels.
- Other pixels equal a per-channel 2–98% stretch computed in the test with stats::quantile over finite samples (within 0.5/255 if depth = 8 is adopted).
- An all-finite image still encodes RGB.
- Zero-denominator ratio pixels are transparent.
- Preview cache:
- Two .image_data_uri calls give identical strings; the second reads nothing (binary_calls unchanged; the lattice reader is called once).
- Changing view, bands or max_dim misses.
- at_close_image misses and removes the old entries.
- After rewriting the ENVI payload (size/mtime change), the cache is not served and at_tile_source reports IMAGE_CHANGED (oracle: .source_status == 'changed').
- After relink, a fresh entry is computed.
- Mutating a hand-built array changes the decoded pixels (oracle: readPNG).
- entries = 4 over 20 images keeps at most 4.
- bytes = 0 disables the cache.
- A reopened-in-call at_tile adds no tile-cache entry (r6 regression).
- Queue handle cap (testServer on .app_server(queue_session(8)), annotatR.app_retained_images = 2):
- Navigate 1→8→1 with key_next and key_prev envelope events.
- After every step, at most 2 entries hold pixels in rv$session and in the store, and rv$project always holds pixels.
- Oracle: .queue_memory_report structure.
- Revisiting an evicted entry:
- at_tile(rv$project$image) equals the array used to write the fixture (exact codes). This is the independent oracle; .tiff_raw_read is the backend's own decoder and is not independent.
- ROI ids, geometry, revision and dirty flags are unchanged.
- Changed source after eviction:
- Rewrite entry 2 with a different size after leaving it, then navigate back.
- The display error mentions the changed source, edits are refused while undisplayed, the session still holds the annotations, and Save persists them.
- Pinned images:
- A hand-built in-memory image without a descriptor is never released.
- An image whose band_names were changed after at_read_image (as at_example_image('multiplex') does) is reported not releasable and still renders after navigating away and back.
- History pruning (annotatR.app_history_entries = 2):
- After edits on entries 1–4, names(rv$history) is a subset of the last two MRU ids.
- Undo on a pruned entry returns FALSE and changes nothing.
- A Save read back with at_load_session contains all four edits.
- Heap stabilisation (skip_on_cran), 30 entries of 400×400×3 TIFF, annotatR.cache_size set small:
- With eviction, R heap Vcells 'used' after a full gc varies by less than 2 decoded handles over steps 10–30.
- With app_retained_images = Inf it grows by at least 15 handles.
- Oracle: object.size of one decoded handle.
- Retention elsewhere:
- After a folder load, rv$recovery_queue holds no releasable arrays; restoring it renders the previous live image.
- .cmd_goto over 5 entries keeps at most the cap of handles in hub$session.
- After Save, rv$session respects the cap, and .save_checkpoint's reload of a NULL entry with a project_path holds no pixel arrays.
- at_batch_apply keeps pixels for entries that had them and returns released images for entries it materialised; at_tile still works.
- at_extract on a project with a released raster image and 5 ROIs calls at_read_image once (counted with a mocked wrapper).
- at_close_image drops the closed identity's tile and preview cache bytes to 0.
- Mask guard:
- With annotatR.max_mask_pixels = 100: 10×10 works; 11×10 raises at_limit_error MASK_TOO_LARGE with details width 11, height 10, pixels 110, limit_pixels 100.
- A virtual 1e6×1e6 project errors with a gc max-used delta below 1 MB.
- at_mask_stack is guarded on pixels × layers.
- Option values -1, NA, 'x' and 0 are rejected; the default is 2^27.
- at_write_masks(stream = 'never') gives an error row with MASK_TOO_LARGE while other rows are 'ok'.
- at_export_qupflowr surfaces the classified error.
- Hand-computed streaming oracle:
- overlap_pair, a triangle and a point on their native 10×10 grid, plus a non-square 7×5 case.
- Literal integer matrices are written in the test for the last, first, max, min and bitor policies; overlap = 'error' raises the same class as at_mask.
- Streamed NPY and TIFF with 1-, 2- and 5-row blocks, read back through at_read_npy and .read_mask_matrix, equal the literals.
- Differential identity on 211×173:
- Inputs: seeded polygons, circles, a thin rectangle across a block boundary, an overlapping pair whose intersection spans every tested block boundary (asserted in the test), and points including (0,0).
- Configurations: binary; labelled last and first; multiclass last, first, max, min and bitor; error on a disjoint set and on an overlapping set (abort equivalence, no files left); values maps with absent classes; background 7; level 1 of a 100/50/25 pyramid; layer and label filters.
- Block rows 1, 7, 16 and H.
- The output equals at_mask. NPY payload equals writeBin(as.integer(t(ref)), size = 4).
- TIFF decoded through .tiff_raw_read and terra noflip equals at_mask and equals the decoded at_write_mask TIFF of the same mask (the direct in-memory comparison).
- Sidecar equality:
- mask_metadata, legend (value, label, layer, roi_id, n_px, colour), mask_type, level and dims equal .write_legend_json(at_mask(...)).
- NPY storage is axes 'yx' with shape (H, W); export.rendering is 'windowed'.
- at_read_mask polygonises the streamed TIFF (stride 1, origin 0 accepted).
- Lattice mask previews: .mask_preview_lattice equals at_mask_preview(at_mask(...), max_dim) for max_dim 37, 100, 256 and 1024 (fac = 1 returns the full mask), across every type and overlap: matrix, legend, and metadata except 'created'. .cover_lattice equals .cover_polygon sampled at the lattice on 120 random polygons, half of them with half-integer vertices.
- Refusals and range checks, with the directory listing unchanged afterwards:
- touches = TRUE or LINESTRING above the limit raise at_capability_error STREAMING_UNSUPPORTED.
- Within the limit, rendering is 'in-memory' and equals at_mask.
- An 8-bit TIFF with code 300 and an int16 NPY with labelled id 40000 are refused.
- A positive 8-bit TIFF decodes exactly.
- Determinism and BigTIFF:
- Two exports give an identical mask sha256.
- With the internal BigTIFF threshold lowered, the magic is 43 and the isolated libtiff and GDAL decodes are exact.
- Bounded streaming memory (skip_on_cran):
- W = 3000, H in {2000, 8000}, two large polygons.
- gc max-used delta during NPY streaming is below 64 MiB and differs by less than 25% between the two heights.
- at_mask at H = 2000 peaks above 5× its output.
- Cancellation:
- progress returning FALSE after block 2 raises at_cancelled_error EXPORT_CANCELLED; no destination, no sidecar and no '.export-stage-*' or '.export-previous-*' files remain.
- With overwrite = TRUE and existing outputs, their sha256 is unchanged.
- rlang::interrupt() from progress behaves the same, as does a mocked sink-commit failure.
- An injected rename that fails, or that interrupts, on the primary publish restores prior files; a recording rename shows the sidecar published first.
- at_export_all with a mocked cancelling writer stops at the cancelled item; earlier bundles stay complete.
- Hard kill (skip_on_cran, callr):
- The child streams a large NPY and TIFF; its progress callback prints 'ready' and blocks after block 2.
- The parent uses p$poll_io, then p$kill(); there is no sleep loop.
- Destination and sidecar are absent.
- Leftover '.partial' stages have zero first bytes; at_read_npy says 'Not a NumPy .npy file.' and .tiff_raw_read errors.
- Qualification lane (not mandatory CI):
- memory-bounds.R records ps RSS and gc trajectories in fresh processes: a 100-entry navigation plateau within 2 handle sizes over the last 20 steps; a 20000² preview adding less than 256 MB RSS; a 12000×9000 streamed export vs at_mask.
- npy-stream-check.py, run with python3 -I, verifies the sha256 with stdlib Python only.

### Acceptance

- Queue memory stabilises after eviction:
- A full-server navigation test bounds retained pixel handles in the session, store, recovery queue, hub and after Save to the configured cap.
- R heap after a full gc stays within 2 handle sizes over 30 visited images, and grows linearly with retention disabled.
- Revisited entries reopen with pixels identical to the fixture arrays.
- Images that cannot be reopened (modified metadata, no descriptor) stay pinned.
- History is pruned to the configured number of entries.
- The qualification script records the RSS plateau for 100 entries (prototype p5: 344–356 MB vs 366→735 MB in p4).
- Preview dimensions obey limits:
- Lattice tests prove dims ≤ max_dim for pyramidal and non-pyramidal images, with values equal to the formula oracle.
- Bytes read follow the per-layout formulas (BSQ/BIL nb, BIP B, SpecCube y-span·B), and previews never fill the tile cache.
- at_plot_image works on a 20000²×3 cube that previously failed with TILE_TOO_LARGE.
- The canvas, which previously read all 2.4 GB, reads about 1/s of the rows.
- Previews are cached by read generation plus display settings and invalidated on close, release, relink or source change.
- Cancelling large exports leaves no valid-looking partial outputs:
- Progress-cancel, interrupt (in the writer and during publication), injected-failure and batch-cancel tests show no destination, no stray stage or backup files, and prior outputs intact.
- A callr SIGKILL leaves only hidden '.partial' stages with zero headers, which at_read_npy and the isolated libtiff reader reject.
- Every mask bundle publishes its sidecar before the mask, so no mask can appear without its legend.
- Streamed outputs are pixel-identical to in-memory results on reference-sized cases, including overlaps across block boundaries:
- Literal hand-computed matrices for every overlap policy with 1-, 2- and 5-row blocks.
- Differential tests against at_mask and against the decoded at_write_mask TIFF across types, overlaps (including the 'error' abort), values maps, background, levels, filters and block heights {1, 7, 16, H}.
- TIFF is verified through two independent decoders (isolated libtiff, GDAL); NPY through at_read_npy and a stdlib Python reader.
- The at_mask matrix contract is preserved with a useful size guard:
- MASK_TOO_LARGE (class limit, with details) is raised before allocation.
- The about 5–9× transient peak is documented.
- An explicit streamed alternative is named.
- Every internal caller either streams (stream = 'auto') or surfaces the classified error.
- Documentation does not claim windowed reads solve full-slide masks. Vignettes and NEWS distinguish:
- bounded source access (T15)
- bounded previews
- bounded queue retention
- bounded streaming export
- materialised at_mask()
- The 'RGB normalization error with nonfinite samples' is fixed and regression-tested: finite-only stretch quantiles, and non-finite pixels drawn transparent as at_plot_image draws them, for both tiny and large previews.

### Out of scope, blocked or needing a decision

- Streaming for touches = TRUE and LINESTRING/MULTILINESTRING/GEOMETRYCOLLECTION ROIs is out of scope.
- GDAL rasterisation depends on the raster extent. Re-run p10: with 20-row blocks, 4/20 integer-vertex polygons differ; changing only the height changes 1/20.
- These cases are rendered in memory within the limit and refused (STREAMING_UNSUPPORTED) above it.
- An exact pure-R all-touched or line rule would change at_mask semantics and needs a maintainer decision.
- OME with RBioFormats cannot be tested here (RBioFormats is not installed).
- The generic per-row fallback IS testable with a registered fake backend, and that test is included.
- cuvis eager images use the direct-index path and are testable with hand-built images. Only real cuvis/SDK reads stay unverified.
- A GDAL-backed windowed TIFF backend is T15 work; p18 shows terra noflip windows are exact, so it could register a lattice reader later.
- An app-level asynchronous export with a Cancel button is out of scope. T16 provides package-level cancellation (progress callback, interrupt) and kill safety; the Shiny export stays synchronous.
- Calibrated RSS and latency budgets and hardware envelopes belong to T17. T16 adds structural CI assertions and the qualification script.
- Needs a user decision: option defaults.
- Proposed: max_mask_pixels 2^27, app_retained_images 3, app_retained_bytes 512 MiB, app_history_entries 10, preview_cache 128 MiB / 16 entries, canvas_max_dim 2048, mask_block_bytes 8 MiB.
- The 2^27 guard makes at_mask refuse masks it produces today (for example 12000×12000) unless the option is raised. This is a breaking change for 0.2.0 that needs NEWS.
- Also decide whether stream = 'auto' should be the default for at_write_masks and at_export_all (proposed: yes; below the limit the bytes are unchanged).
- Needs a user decision: encode canvas PNGs at depth 8 (proposed).
- It halves the URI and transfer size for stretched views (r4) and matches the 8-bit browser canvas.
- It changes the bytes of stretched previews by at most 1/255 per channel.
- The alternative keeps all-finite previews byte-identical.
- Needs a user decision: scope and order.
- The roadmap budgets 3–5 days for T16 and orders T18a (native TIFF crash containment) before it.
- This design needs about 13 focused days.
- Proposed phasing: T16a previews, cache and non-finite fix (D1, D2); T16b retention (D3); T16c guard and streamed export (D4–D7); documentation across all three.
- Alternatively, cut streaming to NPY only and defer the pure-R TIFF/BigTIFF writer. at_export_all's mask_tiff would then return MASK_TOO_LARGE above the limit.
- T16 does not technically need T18a: all TIFF decoding in T16 code and tests uses the existing isolated reader. Running T16 first must be recorded as a deliberate deviation from the roadmap order.
- The control service's mask.preview command and its column-major full-mask sha256 contract are unchanged; it keeps its own pixel budget.
- Streaming the interop handoff masks (at_export_qupflowr, the control 'export' command, .mask_record digests) is out of scope. Its column-major digest needs the full matrix. These paths are guarded and documented.
- Replacing tiff::writeTIFF in at_write_mask with the pure-R writer is out of scope. It would need tifffile/imagecodecs requalification, and none of the local Pythons (3.9.6, 3.15) has tifffile, numpy or PIL installed. Streamed and in-memory TIFFs are pixel-identical but not byte-identical: deflate multi-strip versus libtiff LZW single strip (r1).
- Re-sending the cached multi-MB data URI over the websocket on every canvas re-render is out of scope (renderAtCanvas depends on rv$project, rv$tool, rv$selection and the active label/layer). Moving annotation updates to proxies is a T10/T11-level change; T17 should measure it first.
- Bounding annotation layers of visited entries, and the training export's full at_mask plus per-ROI full-size .cover, is out of scope. Both are guarded but not streamed.
- Streamed masks cannot be read back by annotatR when they are above 2^31 − 1 pixels or when count × 8 exceeds annotatR.max_read_bytes (1 GiB by default, i.e. 2^27 px). at_read_npy is eager, and TIFF read-back decodes doubles in a subprocess. These outputs are documented as written for downstream tools.
- Windows qualification belongs to T18; no Windows host is available here. It covers the header patch through an 'r+b' connection (R documents seek on Windows file connections as unreliable), staged unlinks, and non-sparse large fixtures.

### Risks

- Native TIFF fragility (relates to T18a). r3 confirms that tiff::readTIFF(as.is = TRUE) kills a callr child on a GDAL-tiled TIFF.
- Mitigation: streamed TIFFs are stripped and written in pure R.
- Tests decode only through the isolated .tiff_raw_read (as.is = FALSE) or GDAL.
- GDAL writers silently turn a valid code into NA. r3: terra INT2U defaults to NoData 65535, which reads back as NA; NAflag = NA still writes NoData nan. Avoided because the pure-R writer emits no NoData tag.
- On macOS, RSS does not fall after gc (confirmed in a callr child). CI therefore asserts structural counts and the R heap 'used' after a full gc; RSS is kept for the qualification and performance lanes.
- Released handles are re-decoded when accessed.
- at_tile reopens per call and previously cached each tile under a throwaway identity (r6).
- Mitigations: no cache insert for tiles of a handle reopened inside the call; reopen once in extraction and training; at_batch_apply restores the input handle state instead of releasing everything.
- Remaining cost: about 0.3–0.5 s per eager TIFF revisit (subprocess decode); tunable by option and measured in T17.
- A snapshot whose metadata was edited after reading cannot be reopened (.reopen_image compares band_names, wavelengths and more). Releasing it would leave the entry 'unresolved'. Mitigation: the reopen-field digest pins such images. Without it, entries like at_example_image('multiplex') would break on revisit.
- Retention changes behaviour when the source changes after eviction. A retained snapshot kept displaying the old pixels; a released entry shows IMAGE_CHANGED on revisit while its annotations are kept. This must be documented and tested.
- close_fn is not called on automatic release, because the shared store, the hub and other tabs may hold copies of the same handle. A third-party backend that keeps external resources next to arrays releases them only through GC or an explicit at_close_image.
- The preview cache can mask test mocks: an encoder mock is bypassed by a cache hit on identical content. Tests that mock .view_display_array or the encoder must disable the cache.
- Images with a read_generation key on read identity plus source signature, so an in-place handle mutation of such an image would be served stale. The tile cache has the same property.
- Behaviour changes users will see:
- transparent non-finite and zero-denominator canvas pixels;
- at_mask refuses masks above the limit;
- closing an image purges its caches (reverses a documented vignette sentence);
- sidecar-first publication and '.partial' stage names for every bundle;
- at_batch_apply handle restoration;
- a different TIFF encoder above the limit;
- an 8-bit canvas PNG, if adopted.
All need NEWS entries and a review of downstream expectations.
- The streamed range check works on declared codes, while at_write_mask checks the values actually present. A borderline export can therefore fail when streamed and succeed in memory, for example labelled ids above 65535 that are completely hidden by overlaps. Documented.
- Band means are accumulated in double instead of with mean()'s two-pass long-double algorithm, so they can differ by ulps. They are display-only; tests use a relative tolerance of 1e-12.
- Reusing the T04 membership code. Row blocks use the existing .cover origin path unchanged (p13), and the lattice uses a separate .cover_lattice (p14), so the reviewed .centre_range, .cover_polygon and .cover_shortcircuit are not modified. Differential tests guard both.
- Windows portability of the header patch, staged unlinks and sparse fixtures is unverified (see out_of_scope_or_blocked). Large-file tests use skip_on_os('windows') or moderate sizes.
- Shared store across tabs: one tab's eviction releases stored copies that another tab may revisit. This is functionally safe (reopen) but slower. Live projects are never released.
- The at_mask peak multiplier (5.4–8.5× in p7) may change between R and sf/stars versions. The guard is expressed in pixels, and the multiplier is documented as informational.
- Effort and schedule: the scope is about 2.5× the roadmap's 3–5 days. Without phasing, review cycles will be long; see the scope decision in out_of_scope_or_blocked.

### Depends on

- T01 (read generations and cache identities used for cache keys)
- T02 (entry-aware transitions and per-entry history in R/app-state.R)
- T03 (source descriptors, .reopen_image and .strip_persisted_handle used by retention)
- T04 (centre-membership contract reused unchanged by the windowed renderer)
- T06 (versioned mask metadata, legend and codebook validation reused by streamed sidecars)
- T09 (staged export bundles, plans and receipts extended with sidecar-first publication)
- T15 (partly on main: ENVI/TIVITA window layouts, telemetry, capabilities, at_close_image; the missing GDAL TIFF window path is not needed by T16)
- T18a (roadmap orders it before T16; T16 does not depend on it technically because all TIFF decoding uses the isolated reader; running T16 first must be recorded as a deliberate deviation)

## T17: repeatable performance budgets and regressions (milestone M5). This is the reviewed and corrected specification. Deliverables:
(1) A fresh-process, installed-build benchmark harness in tests/qualification/performance/. It measures cold open, cold and warm window, preview, edit (autosave off and on), navigation, save (by ROI count and by queue length), resume, extraction and export, including the 0.2.0 interop, training and control-service paths.
(2) A mandatory-lane testthat regression showing that a fixed window's bytes and R memory do not grow with cube size.
(3) A calibrated performance section in VALIDATION.md, with a status on every row.
(4) A documented large-image envelope.
Phase A (harness, regression, synthetic baseline with known gaps recorded) can start now. Phase B (re-baselining and adopting gates) waits for T16.

Estimated effort: 32 focused hours.

### Current state

Base: main at review time was 649cf49 (0.2.0 development). This review changed no repository file.

While the review ran, another process changed the working tree:
- Modified: .Rbuildignore (adds node_modules and package.json entries), .gitignore, NEWS.md, R/interop-capabilities.R, R/interop-handoff.R, planning/IMPLEMENTATION.md, planning/ROADMAP.md, planning/evidence/2026-10-18/*, and analytical/interop fixtures.
- New: .gitattributes and tests/testthat/test-export-contract.R.
- IMPLEMENTATION.md now says the port is being rebased onto 288c1c5 and committed as @CODE@.
None of this touches T17 targets. Two consequences: the implementer must find the base commit again, and the harness must handle a dirty tree. T15 is partly ported; T16-T18 are open.

1. Benchmarks (confirmed)
data-raw/benchmark.R `bench()`:
- Reports `system.time` medians only, under `devtools::load_all`.
- Its workloads all start from a preallocated 2048x2048x3 `handle$data`: a cold/warm tile, rectangle vs near-rectangle `at_mask`, `at_mask`/`at_extract` with 100 ROIs, and a PNG read.
- It records no memory, bytes, hardware or versions. This is the "warm-cache-only, arrays already allocated" pattern that ANALYSIS.md item 6 and REGRESSIONS.md "Benchmark fixture inventory" reject.

2. Existing qualification script (confirmed)
tests/qualification/window-resources.R:
- One fresh process per backend: open plus one 64x64 tile.
- Fixtures are sparse all-zero ENVI/TIVITA files, or constant OME files from window-resource-fixtures.py (needs numpy/tifffile). The pixel oracle is only "all 0 or 7".
- Memory comes from /proc/self/status (Linux only), Rprofmem and `.read_telemetry()`. Output is written with `dput`. It loads the code with load_all.
- IMPLEMENTATION.md lists it as not run in the port.
Its evidence (planning/evidence/implementation-2026-09-10/t15/):
- Comes from the pre-port branch on x86_64 Linux.
- envi-512 vs envi-32768: HWM 260.42 vs 260.23 MB (equal within 0.2 MB, not identical); max R allocation 98,352 B in both; binary_bytes 16,457 vs 16,461.
- ome-512 vs ome-16384: 493 vs 577 MB after the tile.
- The speccube files describe the old TIVITA reader (0 open bytes, 8,192 calls). On main, `.tivita_read_speccube` reads the 12-byte header and `.tivita_read_window` makes one call per window column.

3. Instrumentation (confirmed, with nuances; T17 needs no package change)
Read telemetry, R/io-window.R (`.read_telemetry_reset`, `.read_telemetry`, `.read_telemetry_add`, `.window_read_raw`):
- Counts logical bytes and calls of the binary readers.
- `native_file_bytes` starts at 0 and only becomes NA after a native OME call.
- `decoded_bytes` is added only by the window readers (ENVI, TIVITA, OME). Tiles sliced from eager tiff/raster arrays appear only in `at_read_stats`.
Read stats, R/hsi-meta.R `at_read_stats` and `.read_stats_add`:
- Counted per cache identity; cache hits are not counted.
Tile lookup, R/backend.R `at_tile`:
- Calls `.reopen_image` (R/persistence.R) before the cache lookup, so every call validates the descriptor and stats every source file, hits included.
- A closed or stripped image (handle NULL) is reopened on every call with a fresh read generation (from `at_read_image`). Each call therefore re-reads the header plus the window, is never a cache hit, and adds a new cache entry. `at_read_stats` of the caller's image stays at 0.
  - Probe probe-close.R: 327 B (71 header + 256 window) on each of 3 calls; 3 cache entries; tiles = 0.
- `.tile_key` includes the per-read `cache_identity`, so two opens never share cache entries. Stale hits across opens or options are impossible by construction.
R/perf.R:
- LRU cache with `.tile_cache$bytes`, `.tile_cache_limit()` and option annotatR.cache_size (default 512 MiB). Entries larger than the limit are never cached.
R/zzz.R `.register_backends`:
- Declares ometiff as (FALSE, FALSE, "unqualified", "eager"), while `.ometiff_read` sets `.window_capabilities("native")`. So `at_backend_list()` and `at_image_capabilities()` disagree (confirmed). Fixing this is outside T17; the harness reports it.

4. Backends (confirmed)
Window-capable:
- envi: `.envi_read` reads metadata only; windows via `.envi_read_window` and `.envi_read_distinct`.
  - Partial-width BSQ/BIL makes one call per row per distinct band.
  - BIP reads all B bands per row.
- tivita: SpecCube via `.tivita_read_speccube` and `.tivita_read_window`. Needs a matching profile (legacy nx/ny/nb/header or `at_tivita_profile`) and a file named *_SpecCube.dat.
- ometiff: `.ome_window`; needs RBioFormats, which is not installed here.
Eager:
- tiff: `.tiff_read` -> `.tiff_raw_read` -> R/io-tiff-process.R `.tiff_read_isolated`.
  - The child Rscript runs `tiff::readTIFF(all=TRUE)` and saves an uncompressed RDS of every decoded directory (doubles, 8 B per sample) to tempdir. The parent reads it back with `readRDS`.
  - `.tiff_raw_read` then makes several full-size temporaries (`a*(2^bits-1)`, `abs(a-round(a))`, range checks, `round`).
  - This explains a peak of about 4.5-7x the decoded doubles, and means tempdir needs space for the decoded doubles of all levels. Telemetry counts neither the source bytes nor the RDS transfer.
- raster: `.raster_read` via magick.
- cuvis.

5. Workload code paths (confirmed, with additions)
Preview:
- `at_canvas` -> `at_tile_source` -> `.image_data_uri` -> `.view_display_array` -> `.preview_bands` (R/widget-canvas.R).
- Reads full-width row chunks of up to 64 MB for every row of the display bands, then decimates. The chunks go into the tile cache.
- At XL (32768^2) this would mean about 6 GiB logical and 3.2e9 decoded samples.
- `at_plot_image` -> `.image_display_df` (R/plot.R) calls `at_tile(img, level)` for ALL bands of the display level, not only the three shown. On 4096^2x16 that is 2 GiB of doubles, refused by the default 1 GiB read budget (R/io-binary.R `.read_budget`, READ_BUDGET_EXCEEDED). Only S can be plotted.
Edit:
- `.state_mutate` (R/app-state.R). `renderAtCanvas` in `mod_canvas_server` re-runs `at_canvas` on every change to `rv$project`.
- `at_session()` defaults to autosave = TRUE. `mod_session_server` installs `rv$save_callback` as `.app_backup_session(store, c)` followed by `.app_save_checkpoint(c, cur)`.
- `.state_changed` calls `.state_save` synchronously inside every edit, so a default-configuration edit includes a full checkpoint.
- On the first save per queue and store, `.app_backup_session` reads the old _session.rds and hashes every ROI geometry (`.session_roi_keys`).
Save:
- `.save_checkpoint` (R/persistence.R) writes, on every save, one new immutable file per non-NULL project (projects/<stem>-<generation>.rds), checking each with `readRDS` (`.atomic_save_rds`).
- It then rewrites _session.rds, which embeds all projects.
- Old generation files are never deleted (`unlink` only on failure). Cost and disk growth per save are O(entries x ROIs).
Navigation:
- `.state_navigate` -> `.state_snapshot` (stores the live project with its handle in `rv$session$projects` and in the app store) -> `.state_load` -> `.app_load_project` (R/app-builder.R) = `.materialize_project` (R/batch.R).
Resume:
- `at_resume` / `at_load_session` (materialize=FALSE) -> `.materialize_project` -> `.reopen_image`.
Extraction:
- `at_extract` -> `.roi_pixel_values`: one tile per ROI over the `.bbox_range` (`.centre_range` for polygons). Repeated identical windows are cache hits. `at_extract_spectrum` calls `at_extract`.
Export:
- `at_export_all` -> `.export_session_items` -> R/export-policy.R `.export_project_file`. `mask_tiff` builds a full `at_mask()` and has no size guard.
- `.export_bundle` stages .export-stage-* files beside the targets, then renames them. A killed process leaves only the stage files.
- The only mask pixel budget is the control service's annotatR.control_mask_max_pixels (4096^2, R/control-commands.R).

6. 0.2.0 paths the original spec omitted
These read whole source files:
- `at_interop_manifest(hash_sources=TRUE)`, `at_export_qupflowr` (via `.image_record`) and `at_training_export` (training.R line 229) all hash through `.source_files(hash=TRUE)` -> `.sha256_file` (`tools::sha256sum`). This reads every source byte, ENVI header plus payload.
- `at_training_export` also builds full-size masks with `at_mask`.
- The control hub's `.hub_state` (R/control-state.R) hashes the current entry's sources without the lazy cap, through `.hub_image_id(hub, cursor)` (cached by path, size and mtime). Other entries are hashed lazily up to annotatR.control_hash_max_bytes (256 MiB).
- So the shiny-workflow vignette's "nothing is read from disk until you visit it" does not hold with the control service enabled.

7. Existing tests (confirmed)
- test-windowed-readers.R: exact telemetry on tiny fixtures; one 2^31-byte sparse open (bytes = header + 4); stale and relink checks. It uses one size and no memory comparison.
- test-perf.R: a preallocated in-memory extraction gc check.
- helper-fresh-process.R `audit_fresh()` / `fresh_loader()`: uses load_all under devtools and the installed copy under R CMD check.

8. Documentation (confirmed)
- The "Memory discipline" section of the images-and-backends vignette avoids blanket claims and says the counters are not RSS.
- README.Rmd says eager images "must fit in memory".
- VALIDATION.md targets are provisional (p95 <= 250 ms for edit/preview; p95 <= 1 s for save) with no baseline. It also requires "ROI count/vertices" and export "cancellation", which the original spec did not measure.
- DESCRIPTION and README say "across whole-slide microscopy images", but no whole-slide configuration is qualified: OME is unverified and TIFF is eager.

9. CI and machine facts
- The shared R-CMD-check matrix (saved CI log) runs macOS-latest, windows-latest and four Ubuntu R versions, all with NOT_CRAN=true. `skip_on_cran()` tests therefore run on Windows, where NTFS does not create sparse files from seek+write.
- The review machine (Apple M1, 16 GiB) had 11.4 of 12 GiB swap in use and ps_system_memory avail 4.6 GB. Timing evidence from it is indicative only.

10. What the T17 acceptance criteria still lack
- Fresh-process installed-build measurements of every workload, including autosave edits and checkpoints by queue length, the 0.2.0 export and hashing paths, and export cancellation.
- A portable peak-memory measure with validity flags.
- Physical/logical byte sources per OS, with an OS-cache label.
- Machine-readable results with hardware, versions, ROI counts and vertex counts.
- A two-size non-scaling regression in the mandatory lane.
- Calibrated VALIDATION rows and a documented envelope.

11. Probe observations
(a) Original scoping probes: n=1, Apple M1, installed build, about 3 GiB free; kept as reported.

Window on 2048^2x8 uint16 ENVI:

| Phase | Result |
|---|---|
| Open | 4 ms |
| Cold 256^2x8 window | 134 ms, 1.00 MiB, 2,048 calls |
| Cache hit | 1 ms, 0 B |

Preview (2048^2x8 ENVI):
- Decode: 1.21 s, heap 529 MiB, max RSS +674 MiB, 16 MiB read. The fixture had only two distinct RGB bands.
- Logical bytes grow with area: 16 vs 64 MiB at 2048^2 vs 4096^2.
- With PNG encode: 2.69 s.

Other workloads:
- Edit + render: 2.40 s, 0 bytes read.
- Project save: 5 ms.
- 51-ROI extraction: 1.20 s.
- mask_tiff export: heap 302 MiB at 2048^2.

Measurement-mode effects:
- Under load_all a cache hit took 65-89 ms and 45 MiB of heap.
- Installed baseline RSS after `library(annotatR)`: 93 MiB.

Eager TIFF open, max RSS increase in a fresh worker:

| Size | Max RSS increase |
|---|---|
| 1024^2 | +57 MiB |
| 2048^2 | +145 MiB |
| 4096^2 | +624 MiB (k about 4.5-7) |

Navigation over 12 entries of 1024^2:
- PNG queue: +49 MiB per entry (cache plus retained arrays).
- ENVI queue: +24 MiB per entry (cache only).
- File descriptors constant at 9.

Single-project save time:

| ROIs | Save time |
|---|---|
| 15 | 18 ms |
| ~105 | ~40 ms |
| ~1005 | ~0.32 s |

The project file is about 340 B per ROI.

Startup and resume:
- R start 0.21-0.24 s; `library` 0.11-0.13 s.
- Resume to the first window: 0.16-0.71 s, bytes = header + window.

(b) Review probes. All are in <scratch> The machine was swapping, so treat timings as indicative.

probe-bounds.R: the spec's testthat design (4 bands, 512x384 vs 16384x6144, sparse with a formula patch over x 129..384, y 65..320):

| Case | Bytes (small / large) | Calls |
|---|---|---|
| BSQ | 524,361 / 524,364 (header + 524,288) | 1,025 |
| BIP | 524,361 / 524,364 (header + 524,288) | 257 |
| SpecCube | 1,048,588 (12 + 1,048,576) | 257 |

- Heap difference: 96-160 B. Total allocation difference: 16-32 B. Max allocation: 2,097,200 B for both sizes.
- All checks pass in both load modes, and with either a 64x48 warm-up using the in-extent window x/y 1..32 or the small cube as warm-up.
- Wall time for all three cases: 2.2 s installed, 7.5 s with load_all.

probe-open-heap.R: first open in a fresh installed worker:
- Heap 1.56 MiB, allocations 0.49 MiB, max allocation 32,400 B, maxrss +0.5 MiB, 73 B read.
- Start to `library`: 0.19-0.26 s; `library` 0.11-0.17 s; open 4-9 ms.

probe-edit-server.R and probe-edit-server2.R, 1024^2x16 ENVI:
- Component path (mutate + `at_canvas`): 0.96-1.32 s. Widget JSON: 0.02-0.03 s for a 2.48 MB payload.
- `shiny::testServer(.app_server)` edit flush: 0.74-2.04 s with one preview encode. The flush also ran `at_mask` twice, `at_rois_overlap`, `at_extract` and `at_plot_mask`, which are mask/HSI outputs a browser would suspend while hidden.

probe-save-queue.R (`.save_checkpoint`, N entries x 100 ROIs):

| N | Time per save | Project files after 3 saves | _session.rds |
|---|---|---|---|
| 1 | 0.02 s | 1 / 2 / 3 | 6.7 KiB |
| 10 | 0.13-0.14 s | 10 / 20 / 30 | 59.3 KiB |
| 50 | 0.62-0.68 s | 50 / 100 / 150 | 292.1 KiB |

probe-autosave-edit.R (default autosave, app constructors and callback): one ROI edit costs 0.08-0.11 s at N=1, 0.22-0.45 s at N=10 and 0.85-2.27 s at N=50, and writes N files per edit.

probe-child-mem.R:
- The parent can read a child's rss with `ps_memory_info`; `ps_memory_full_info` gives "Permission denied".
- `ps_children(recursive=TRUE)`: 11 ms. `ps_memory_info`: 20 µs.

rusage.py + probe-rusage.R:
- libproc `proc_pid_rusage` (RUSAGE_INFO_V4) works unprivileged through python3 ctypes.
- `ri_diskio_bytesread` did not change on a 64 MiB read of a cached file. It counts physical reads only.
- `ri_diskio_byteswritten` and `ri_lifetime_max_phys_footprint` are available.

Other probes:
- `tools::sha256sum` of a 1 GiB sparse file: 6.46 s (159 MiB/s).
- R `file.copy` turns a 256 MiB sparse file (16 KiB allocated) into a dense one (262,144 KiB allocated).
- Re-run of probe-gdal-from-envi.R at 2048^2: the COG has 4 levels (5 at 4096^2), and stars and annotatR tiff windows equal the formula.

### Design

A. Location and entry point (kept, with corrections)

Location:
- New directory tests/qualification/performance/. It is build-ignored through `^tests/qualification$`.
- data-raw/benchmark.R becomes a pointer that runs the quick profile.
- tests/qualification/window-resources.R stays unchanged, because it reproduces the archived T15 Linux evidence. P02 and P12 are documented as its successors.
- No DESCRIPTION change is needed.
  - The harness checks `requireNamespace` for ps and processx (both installed with callr), sf, stars, png, magick, shiny, htmlwidgets, jsonlite and httpuv (P14).
  - A missing package gives a skip with reason not_installed:<pkg>.

Entry point:
`Rscript tests/qualification/performance/run.R --profile quick|baseline|release [--out DIR] [--fixtures DIR] [--keep-fixtures] [--load-mode installed|load_all] [--reps N] [--warm-reps M] [--scenarios P00..P14] [--sizes S,M,L,XL] [--queue-lengths 1,10,100] [--os-cache prewarm|drop|uncontrolled] [--mem-cap-frac 0.6] [--timeout 900] [--baseline prev/summary.csv] [--seed 20261018] [--machine-label TEXT] [--hash-xl] [--force] [--evidence DIR] [--self-test]`

Defaults (nothing is written into the repository):
- Output: `tools::R_user_dir("annotatR", "cache")/perf-runs/<run_id>`.
- Fixtures: `.../perf-fixtures-v1`. S and M are kept; L and XL are deleted unless `--keep-fixtures` is given.

B. Build under test and process model

Building from tracked sources only:
1. Copy the working-tree content of the files listed by `git ls-files -z` into a scratch directory. This includes uncommitted edits to tracked files. It excludes untracked and ignored files such as hsi-workbench/.
2. Run `R CMD build --no-build-vignettes --no-manual`, which applies .Rbuildignore.
3. Run `R CMD INSTALL --library=<out>/lib <tarball>`.
4. Record the HEAD SHA, the dirty flag, the sha256 of `git diff HEAD`, the sha256 of the tarball, and the list of excluded untracked files.
- Evidence mode refuses to run if untracked files exist under R/ or inst/.
- Evidence mode also refuses if the diff hash changes between the start and end of the run. A concurrent tree change was observed during this review.
- This replaces the rsync copy. R CMD INSTALL on a directory ignores .Rbuildignore and would install, for example, inst/shiny/annotatR/hsi-workbench if present.
- The build makes no repository writes (no git stash).

Load mode:
- An installed, byte-compiled build is mandatory for evidence.
- `--load-mode load_all` runs are labelled `noisy_jit` and excluded from gates.

Workers:
- Each job (scenario x fixture x repetition) is one fresh worker: `processx::process$new(Rscript, c("--vanilla", worker.R, request.rds))`.
- The worker sets `.libPaths` from the request, then calls `library(annotatR, lib.loc=)`.
- Workers run one at a time.
- Each worker appends a JSON line after every phase, so partial results survive a kill.

Orchestrator sampling of the worker tree:
- Every 20 ms: `ps::ps_memory_info(h)["rss"]` (about 20 µs per call).
- Every 100 ms: refresh the descendant list with `ps::ps_children(h, recursive=TRUE)` (about 11 ms). This covers the isolated TIFF decoder.
- Samples go to `samples/<job>.csv.gz`.

Limits:
- If tree rss exceeds `--mem-cap-frac` x available memory at start, the orchestrator runs `kill_tree` and the status is `resource_cap`.
- A job past `--timeout` gets status `timeout`.

C. Per-phase measurements (measure.R `perf_phase(ctx, name, expr, checks, profile_alloc)`)

Time:
- `proc.time()` deltas: elapsed, user, system and child times. Child times include the TIFF decoder, which `system2` waits for.
- `since_process_start_s = Sys.time() - ps::ps_create_time(ps::ps_handle())`.
- A startup record holds R start and `library` time (probe: 0.19-0.26 s and 0.11-0.17 s).
- Latency samples run with Rprofmem off. Allocation profiles come from a separate repetition.
- The `gc(full=TRUE, reset=TRUE)` before each phase is outside the timed region, and this is documented.

R heap:
- `base = sum(gc(full=TRUE, reset=TRUE)[, "used"] * c(56, 8))`.
- `heap_peak = sum(gc()[, "max used"] * c(56, 8)) - base`.
- Only symmetric sequences are compared.

Allocations:
- `utils::Rprofmem` with threshold 0 for open, window and extract phases, and 64 KiB for heavy phases.
- Records `alloc_max` and `alloc_total`.

Process memory:
- macOS: `ps::ps_memory_full_info(self)` gives rss and the lifetime `maxrss`; the worker self-reports (parent access is denied). Optionally, `ri_lifetime_max_phys_footprint` from macos_rusage.py.
- Linux: /proc/self/status VmRSS/VmHWM, after writing "5" to /proc/self/clear_refs before each phase (unverified here).
- Windows: `peak_wset` from `ps_memory_info` (unverified).
- Plus the sampled tree peak, which is a lower bound.
- On macOS, the phase of interest runs first in its own worker.

Validity flags:
- Per-phase page-ins: macOS `pageins` from `ps_memory_info`; Linux majflt from /proc/self/stat.
- Delta of `ps_system_swap()$sin`.
- Either one sets `memory_pressure=TRUE`. Flagged samples are excluded from latency gates.

Bytes:
- Logical telemetry deltas, with the semantics above: native_file_bytes NA after native calls; decoded_bytes counted for window readers only.
- `at_read_stats(img)`, only for images with a live handle. Closed or stripped images use telemetry instead.
- `hashed_bytes`, a structural value: the sum of `.source_files(img, hash=FALSE)` sizes for paths that hash.
- `written_bytes` and `files_written` (from directory listings before and after).
- `.tile_cache$bytes` and `ps_num_fds`.
- OS level:
  - Linux: /proc/self/io rchar and read_bytes, plus best-effort sampling of /proc/<child>/io.
  - macOS (optional): physical `ri_diskio_bytesread` and `ri_diskio_byteswritten` from `python3 -I macos_rusage.py <pid>`, queried outside the timed region.
  - Otherwise NA. Field `os_read_source` records the source.

OS page-cache label on every record:
- `prewarm`: read every fixture once before the job.
- `drop` (Linux): `dd if=F iflag=nocache count=0 status=none`. Verified only if read_bytes > 0 in the first read phase.
- `uncontrolled`.
- On macOS a cold cache can be detected afterwards (`ri_diskio_bytesread` > 0) but never forced without `sudo purge`.
- "Cold" always means a cold process.

D. Fixtures (fixtures.R, generator v1, deterministic)

Formula and writers:
- `perf_value(y, x, b) = ((x-1)*7919 + (y-1)*104729 + (b-1)*1299709) %% 65521`, with 1-based indices.
  - Exact in uint16 and float32.
  - The smallest aliasing shift within ±255 px and ±15 bands has L1 norm 71.
  - PNG/RGB fixtures use `%% 251`.
- `perf_write_envi` and `perf_write_speccube`: base-R streaming in blocks of at most 2^20 samples, dense or sparse with a dense region. About 12-16 s/GiB.
- ENVI headers declare 16 bands at 450 + 20(b-1) nm. The default RGB view then selects bands 10, 6 and 1.

Derived TIFF/COG fixtures:
- Built with `sf::gdal_utils("translate", ...)`, as in the spec. The 2048^2 TIFF is cut from M with `-srcwin`. COGs have 4 levels at 2048^2 and 5 at 4096^2.
- Each eager fixture records the decoded-double bytes of ALL directories, for the preflights.

Ladder (kept):

| Fixture | Sizes / layout | Notes |
|---|---|---|
| envi-bsq-u16 | S 1024^2x16, M 4096^2x16, L 8192^2x16 | dense |
| envi-bip-u16 | M | dense |
| envi-bsq-u16-XL | 32768^2x16 | sparse; dense over [1,1024]^2 |
| tivita-device | 640x480x100 | default profile |
| tivita-XL | 8192^2x100 | sparse; dense over [1,512]^2; explicit nx/ny/nb or `at_tivita_profile`; name *_SpecCube.dat |
| tiff-u16 | 1024, 2048, 4096 (8192 in release) | |
| cog-u16-4096 | DEFLATE and NONE | |
| aniso pyramid | 3000x2000 / 1000x1000 / 300x250 | b = level+1 |
| png-rgb | 512, 1024, 2048 | |
| queues | png512-N, envi512x8-N | entry i offsets b by i |
| ome (optional) | via window-resource-fixtures.py | |

ROI fixtures:
- Built once per fixture-set version: seeded quarter-pixel rectangles, 64-segment circles, 33-vertex polygons, and hole/MultiPolygon variants.
- Saved as RDS in the fixture cache and reused for every size, so ROI ids and timestamps are identical. Vector export bytes are then comparable across sizes.
- The manifest records ROI count and vertex count per geometry type.

Manifest fixtures.json:
- Generator version, parameters, files with logical and `du -k` allocated bytes, sparse flag, sha256 (dense files of 4 GiB or less), GDAL version, and generation time.

Verification (`perf_verify_fixture`), independent of annotatR:
- ENVI, GTiff and COG: windows read with `stars::read_stars(RasterIO=)` and compared with the formula.
- SpecCube: a GDAL raw VRT (VRTRawRasterBand with ImageOffset 12+4(b-1), PixelOffset 4*H*B, LineOffset 4*B, ByteOrder MSB) compared with the formula.

Sparse files and preflight:
- Sparse support is detected with `du`; without it XL is skipped as `sparse_unsupported`.
- Sparse fixtures are never copied with R, because `file.copy` makes them dense.
- Preflight checks free disk in the fixture dir and in tempdir. The TIFF decoder transfer needs the decoded doubles of all levels.

E. Scenarios (scenarios.R)

Conventions:
- `ns <- asNamespace("annotatR")`. All windows lie inside [1,1024]^2; the standard window is x 129..384, y 65..320. TIVITA windows lie inside [1,480].
- `perf_window_bytes`:
  - BSQ/BIL partial width: 256 x nb x 256 x bps.
  - BIP: 256 x 256 x B x bps.
  - SpecCube: 256 x 256 x B x 4.

Default applicability (overridable):

| Scenario | Fixtures |
|---|---|
| P01, P02, P03 hits/grid, P08, P09 | S/M/L/XL and all eager fixtures |
| P03 stale/relink | S scratch copies only |
| P04 | cold S/M/L; warm S/M; at_plot_image S only; never XL |
| P05 | S (n >= 20) and M (n = 3); never L/XL |
| P06 | queue fixtures only |
| P07 | images S and XL; N in {1, 10, 100}; K in {10, 100, 1000} |
| P10 vector formats | S/M/L/XL |
| P10 mask_tiff | S/M, L after mask preflight; never XL |
| P10b | S/M; L in baseline; XL only with --hash-xl |
| P11 | S |
| P13 | M |
| P14 | S/M/L |

App-state setup shared by P05 and P07 (the app's own constructors):
```r
s <- ns$.state_identify(at_session(paths, labels = "a", out_dir = scratch, autosave = A))
store <- ns$.app_store(s)
rv <- ns$.app_state(s, store = store)
ns$.state_init(rv, load_project = ns$.app_load_project)
ns$.state_load(rv)
rv$display_ready <- TRUE
rv$save_callback <- function(c, cur) {
  ns$.app_backup_session(store, c)
  ns$.app_save_checkpoint(c, cur)
}
```
The save callback is copied from `mod_session_server`.

Scenarios:

| ID | Name | What it does | Checks / recorded |
|---|---|---|---|
| P00 | baseline-process | Startup and idle only | Subtraction baselines |
| P01 | open-cold | Open in a fresh worker | Window-capable: bytes = header size (ENVI) or 12 (SpecCube); no `.holds_pixel_arrays`; heap <= 16 MiB (observed 1.56 MiB). Eager: decoded doubles of all levels and k = maxrss increase / decoded bytes |
| P02 | window-cold | Open, then the standard window; separate worker variant reads bands c(1, mid, B) | Pixels equal the formula; bytes = header + `perf_window_bytes` |
| P03 | window-warm | Hits, grid misses (1+64k), reopen-after-close, two separate opens, stale check | See P03 below |
| P04 | preview | `.view_display_array(img, NULL, 2048L)`; `at_tile_source(img, embed = TRUE)`; `at_plot_image` + `ggplot_build` on S | See P04 below |
| P05 | edit | See P05 below | Latency split, render_payload_bytes, files_written |
| P06 | navigation | See P06 below | Per step: live heap after full GC, rss, cache bytes, retained snapshots, history length, fds |
| P07 | save | See P07 below | Elapsed, files, bytes, cumulative growth |
| P08 | resume | Fresh worker after an unmeasured setup checkpoint: `at_resume`, `.materialize_project`, first window, `at_tile_source` | since_process_start per step; bytes = header + window |
| P09 | extract | See P09 below | Bytes and exact means |
| P10 | export | See P10 below | Receipts, exact mask, cancellation |
| P10b | interop | See P10b below | Elapsed, heap/RSS, hashed and written bytes |
| P11 | cache-eviction | cache_size 16 MiB; 12 distinct 256^2x16 windows | Bytes <= limit after each put; newest repeat is a hit (0 B); oldest repeat is a miss |
| P12 | ome-window | Optional OME window read | Ratio gate G-OME |
| P13 | mask-sweep | `at_mask(p, "labelled")` on M dims, K in {10, 100, 1000}, mixed geometry | Timing and memory; rectangle subset exact |
| P14 | control-state | See P14 below | First vs cached state read |

P03 details:
- Hits: 0 bytes, tiles unchanged, identical values.
- Grid misses: windows at offsets 1+64k.
- Reopen after close: each `at_tile` on a closed image reads header + window bytes, is never a hit, and adds one cache entry. `at_read_stats(closed)$tiles` stays 0. Recorded as an envelope fact, not a failure.
- Two separate opens of the same file share no cache entries (0 hits).
- Stale check on S copies only (header and payload variants): `Sys.setFileTime(..., mtime + 2)` gives IMAGE_CHANGED for cached and uncached windows. Then `at_relink_source` gives values identical to the formula.

P04 details:
- Output dims <= 2048, checked by decoding the data URI with `png::readPNG(jsonlite::base64_dec(sub("^data:image/png;base64,", "", uri)))`.
- `at_plot_image` on M ends as `limit_refused:READ_BUDGET_EXCEEDED`, an envelope fact.

P05 details:
- Setup: as above. Each sample, inside `shiny::isolate`:
  1. `.state_mutate(rv, ...)` adding one quarter-pixel rectangle.
  2. `w <- at_canvas(rv$project$image, project = rv$project, tool = "rect", view = rv$view, options = <as renderAtCanvas>)`.
  3. `htmlwidgets:::toJSON(w$x)`.
- Variants: autosave FALSE with N = 1; autosave TRUE with N in {1, 10, 100} saved entries x K = 100.
- Overlay variant adds `.current_mask(rv)` and `.mask_data_uri(m)`.
- Upper bound: one `shiny::testServer(ns$.app_server(s))` run with `session$setInputs("canvas-canvas_created" = envelope)` and `flushReact`. It is labelled "full flush including outputs a browser suspends while hidden".

P06 details:
- Same constructors, with the app store.
- `options(annotatR.cache_size = 64 MiB)`.
- Each step: `.state_navigate(rv, i)`, then `at_canvas(...)`, then `rv$display_ready <- TRUE`.

P07 details:
- `at_save_project(p, path, overwrite = TRUE)` x M.
- Checkpoint with the P05 rv and autosave FALSE: `.state_mutate` then `.state_save`, for N entries x K ROIs.
- The first save is reported separately, because it includes `.app_backup_session` reading the old _session.rds and hashing ROI keys.
- Per save: elapsed, files_written, bytes written, _session.rds bytes, and cumulative projects/ files and bytes after M saves.

P09 details:
- Run `.tile_cache_clear()` before each phase.
- Phase 1: `at_extract(p, stat = "mean")`. Phase 2: `at_extract_spectrum(p)`. Without the clear, phase 2 would read 0 bytes because it hits the cache.
- Byte oracle: sum over DISTINCT (xrange, yrange, bands) windows of the centre-rule bounding box, computed in the harness by re-implementing `.centre_range` arithmetic, times layout bytes.
- Rectangle means equal the mean of the formula over independently computed member cells (tolerance 1e-9).

P10 details:
- Vector formats: `at_export_all(s, dir, formats = c("geojson", "qupath", "csv", "rds"), scope = "all", progress = FALSE)`.
- mask_tiff on a rectangles-only project: non-overlapping rectangles plus one deliberate overlap pair.
- Mask oracle: `tiff::readTIFF(as.is = TRUE)` equals a labelled matrix painted with centre-rule arithmetic. Values are mapped through the exported legend sidecar (roi_id to value), with overlap "last" in the project's ROI order.
- Cancellation: a separate worker running a mask_tiff export at M/L is killed (`kill_tree`) partway through. Oracle: no file exists at any receipt or target path. Leftover .export-stage-* files are recorded, not counted as outputs.

P10b details:
- `at_interop_manifest(s, hash_sources = TRUE)` and `(hash_sources = FALSE)`.
- `at_export_qupflowr(s, dest)`.
- `at_training_export(s, dest, tile_size = 256L)`.
- Training-export memory is envelope-only: it builds full masks, which is known_gap(T16).

P14 details:
- `h <- at_control_start(s, control = "loopback")`; `hub <- ns$.control_hub(h)`.
- Navigate, then time the first `ns$.hub_state(hub)` (hashes the current sources) and a second, cached one.
- Record hashed_bytes and annotatr.control_hash_max_bytes. Finish with `at_control_stop(h)`.

F. Profiles, overrides and preflights

| Profile | Cold reps | Warm reps | Sizes | Nav N | K | Queue N | TIFF sides | Estimated time |
|---|---|---|---|---|---|---|---|---|
| quick | 3 | 10 | S, M, XL | 30 | 10, 100 | 1, 10 | 1024, 2048 | about 10 min |
| baseline | 5 | 20 | S, M, L, XL | 100 | 10, 100, 1000 | 1, 10, 100 | 1024, 2048, 4096 | 45-60 min, plus about 3 min first-time fixture generation, about 4 GiB of fixtures |
| release | 10 | 30 | as baseline | as baseline | as baseline | as baseline | adds 8192 | adds Linux cache drop, the OME lane, and XL hashing (about 3.5 min per 32 GiB hash at 160 MiB/s) |

Per-scenario overrides:
- P05/P07 latency: one worker x n warm samples (S: n >= 20; M: 3).
- P06: 1-2 cold reps.
- P04 at L: 3 cold reps.

Planning:
- Jobs are shuffled with the seed and the order is recorded.
- The plan prints an estimate based on the previous run's medians.

Preflights:
- Eager TIFF memory: 7 x decoded doubles of all directories + 150 MiB.
- Eager TIFF disk: tempdir free space >= decoded doubles of all directories.
- Mask memory: k_mask x W x H x 8 + 150 MiB, with k_mask = max(10, observed on S/M).
- Failures skip with `insufficient_memory_headroom` or `insufficient_disk`.

Baseline guard:
- The baseline profile refuses to start if available memory is below 4 GiB, or if swap-ins occur during a 10 s pre-check, unless `--force` is given. The run is then flagged.
- The review machine (11.4 GiB swap used) would be refused.

G. Outputs (schema-versioned; jsonlite `auto_unbox = TRUE, na = "null", digits = NA`)

results.jsonl (schema annotatr-perf-result-v1). Fields:
- The fields from the original spec.
- Plus: roi_vertices, queue_entries, autosave, files_written, cumulative_files, cumulative_bytes, hashed_bytes, pageins_delta, memory_pressure, os_read_source, limit_code.

Status taxonomy:
- `ok`.
- `functional_failure`.
- `error`.
- `limit_refused:<code>`: expected annotatR limit conditions (READ_BUDGET_EXCEEDED, TILE_TOO_LARGE, MASK_TOO_LARGE). An envelope fact, not an error.
- `resource_cap`, `timeout`.
- `skipped:<reason>`.
- Timing never changes status.

Other files:
- environment.json: as in the original spec, plus python3/libproc availability, the swap and page-in pre-check, the excluded untracked files, and the tarball sha256.
- fixtures.json.
- samples/*.csv.gz.
- summary.csv: median; p95 when n >= 20 and samples are unflagged; MAD.
- summary.md.

Exit code: non-zero on functional_failure, error, or a failing gate that is not a known gap.

H. summarize.R

Functions: `perf_read_results`, `perf_summary_table`, `perf_gates`, `perf_envelope`, `perf_compare_baseline`, `perf_compare_deterministic`, `perf_write_markdown`.

Gates (each reported as pass, fail, not_applicable, known_gap(owner) or known_gap_now_passing, with observed value, threshold and evidence rows):

| Gate | Rule |
|---|---|
| G-WIN-BYTES | Window bytes minus header bytes identical at S/M/L/XL for each window-capable backend |
| G-WIN-HEAP | Cold-window heap spread <= 1 MiB |
| G-WIN-RSS | maxrss/HWM increase spread <= max(32 MiB, 25% of the S increment). The "5% of XL decoded" clause is dropped: 5% of 128 GiB is 6.4 GiB, so it could never fail |
| G-OPEN-META | As in P01 |
| G-WARM-HIT | 0 bytes, tiles unchanged, identical values |
| G-STALE | IMAGE_CHANGED raised, then identical after relink (S) |
| G-PREVIEW-DIMS | Dims <= max_dim. Known gaps (T16): area-proportional preview reads, and `at_plot_image` reading all bands |
| G-NAV-BOUND | Live-heap slope over steps N/2..N <= 0.5 MiB per entry at cache_size 64 MiB. Eager queues are known_gap(T16) |
| G-SAVE-STRUCT | Saved project has `readRDS(f)$image$handle` NULL; project bytes S vs XL for the same ROI objects differ by <= 1 KiB; files per save = number of non-NULL projects. Replaces the old [5, 15] ratio rule |
| G-SAVE-QUEUE | known_gap, owner to be decided: checkpoint time and bytes per save grow with entries x ROIs; generation files accumulate with no retention |
| G-RESUME | Bytes = header + window; max RSS spread across sizes <= 32 MiB |
| G-EXTRACT | Distinct-window byte oracle; heap spread <= 1 MiB; means exact |
| G-EXPORT | Receipts ok; mask exact; vector bytes identical S vs XL for reused ROI objects; cancellation leaves no target-path file. Mask memory is known_gap(T16) |
| G-HASH | Envelope: interop and control hashing read every source byte; hashed_bytes = source sizes; time recorded |
| G-CACHE | As in P11 |
| G-OME | Provisional, as in the original spec |
| G-DETERMINISM | Logical bytes and dims identical across reps |
| G-EDIT-P95 | On S only; n >= 20; unflagged samples; agreed reference configuration; autosave FALSE and TRUE reported separately |
| G-SAVE-P95 | Same conditions as G-EDIT-P95 |

Envelope (`perf_envelope`):
- Per backend and fixture: status, peak memory, k factors for eager TIFF and mask, medians, and the largest size at which every structural gate passed.
- Window-capable sizes are stated as "verified up to <size> logical (sparse) / <size> dense"; anything larger is unverified.
- Additional envelope lines: autosave and checkpoint cost by queue size; hashing cost of interop/control; tempdir need of the TIFF decoder.

Baseline comparison:
- A timing flag is "suspected" when the median exceeds the baseline median by more than max(25%, 3 x MAD/median). It becomes "confirmed" only when a second run reproduces it.
- Flags are advisory and never fail the run.

Deterministic comparison (`perf_compare_deterministic`): bytes, dims, check outcomes and fixture hashes must match.

Self-test (`--self-test`):
- Generate the S fixtures twice and compare sha256.
- Run `perf_verify_fixture`, including the SpecCube VRT.
- Feed hand-built records to `perf_gates`, including limit_refused and known_gap_now_passing cases.

I. tests/testthat/test-resource-bounds.R (mandatory lane, `skip_on_cran()`; verified by probe-bounds.R)

Fixtures:
- Base-R writers in the test: `bounds_envi(dir, w, h, interleave)` and `bounds_speccube(dir, w, h)`.
- Sparse via seek to the last byte, with a dense formula patch over the window only.
- Formula: `perf_value` restricted to 4 bands. The old `(100*b + 10*y + x) %% 65536` maps a shift of one row and ten columns to the same value.
- Sizes: 4 bands; small 512x384; large 16384x6144 (768 MiB ENVI, 1.5 GiB SpecCube, both below 2^31).
- Window: x 129..384, y 65..320.
- Warm-up: two open+window reads of a 64x48 cube with the in-extent window x/y 1..32, or of the small cube itself. Both were verified.

Process:
- One `audit_fresh()` process per case (envi-bsq, envi-bip, tivita). Files are created and deleted per case.
- Inside the process, for small then large:
  1. `.tile_cache_clear()`, `.read_telemetry_reset()`.
  2. `base <- sum(gc(full = TRUE, reset = TRUE)[, "used"] * c(56, 8))`.
  3. `Rprofmem(log, threshold = 0)` when `capabilities("profmem")`.
  4. Open (record open_bytes), read the window, `Rprofmem(NULL)`.
  5. `heap <- sum(gc()[, "max used"] * c(56, 8)) - base`.
  6. Repeat the read: it must read 0 bytes and return an identical result.

Expectations:
- Tile equals the formula at both sizes.
- `window_read` TRUE; `handle$data` NULL; `object.size(img)` < 64 KiB.
- open_bytes equals the header file size (ENVI) or 12 (SpecCube).
- Total bytes = header + layout arithmetic:

| Case | Window bytes | Calls |
|---|---|---|
| BSQ | 256*4*256*2 | 1,025 |
| BIP | 256*256*4*2 | 257 |
| SpecCube | 256*256*4*4 | 257 |

- binary_calls and the `at_read_stats` triple are identical between sizes.
- |heap_large - heap_small| <= 64 KiB (observed <= 160 B).
- With profmem: alloc_max identical and <= 256*256*4*8 + 64 KiB (observed 2,097,200 B); |alloc_total difference| <= 16 KiB (observed <= 32 B).

Runtime: 2.2 s installed and 7.5 s with load_all on APFS.

Windows CI:
- NOT_CRAN = true, so the test runs on windows-latest, where NTFS writes the files densely (up to 1.5 GiB per case).
- R documents `seek` on Windows as unreliable, and seek-for-write is not yet proven there.
- The first CI run must confirm it. Fallback: a large size of 8192x3072 (192/384 MiB, still 128x the small cube). A Windows skip is allowed only with an explicit reason, never silently.

J. Calibrating VALIDATION.md (kept, with additions)

Table columns: Measure | Gate type (structural/latency/envelope) | Gate | Baseline (config, date, SHA, evidence link) | Status (adopted / provisional-unmeasured / not met (owner) / known gap (owner)).

Structural gates:
- Adopted only after the baseline profile passes on the reference configuration.
- R-heap and byte variants are enforced by test-resource-bounds.R in CI; process-memory variants at release candidates.

Latency targets (edit/preview p95 <= 250 ms; annotation-only save p95 <= 1 s):
- Evaluated only on S, with n >= 20 unflagged samples, on the agreed reference machine.
- Never tightened to measured headroom and never loosened to fit a failing baseline.
- A miss is recorded as "not met on <config>: p95 = X" (owner T16 for preview/edit; owner to be decided for queue-length save).

New rows:
- Edit with autosave by queue length.
- Checkpoint growth.
- Interop/control hashing.
- TIFF tempdir transfer.

Wording rules (kept):
- Only "verified up to" sizes, always with configuration, n and statistic.
- Synthetic fixtures are labelled synthetic.
- No "larger than memory" or speed claim without a gate.
- Eager backends are stated as "peak about k x decoded doubles + base".

Recalibrate after T15/T16 changes, a GDAL/magick/R major version change, or a hardware change. Real fixtures remain external prerequisites.

K. Probes

Original scoping probes (scope/): probe-maxrss.R, probe-sampler.R, probe-tiff-backend.R, probe-eager-tree.R, probe-window-scaling.R, probe-workloads(-mode).R, probe-navigation.R, probe-save-resume.R, probe-coldstart.R, gen-envi.R, probe-gdal-from-envi.R, probe-cog.R, proto-test-resource-bounds.R, proto-debug.R. probe-terra-stream.R and probe-noflip.R are T15/T16 context only; T17 uses neither terra nor windowed TIFF.

Review probes (scope/t17-review/): probe-bounds.R, probe-open-heap.R, probe-edit-server.R, probe-edit-server2.R, probe-save-queue.R, probe-autosave-edit.R, probe-close.R, probe-child-mem.R, rusage.py, probe-rusage.R.

### Files

- `tests/qualification/performance/run.R`: New orchestrator CLI.
- perf_parse_args.
- perf_build_install: git ls-files snapshot -> R CMD build --no-build-vignettes --no-manual -> R CMD INSTALL --library=<out>/lib. Records SHA, dirty flag, diff and tarball sha256, and excluded untracked files. Refuses evidence mode on untracked R/ or inst/ files or a tree that changes during the run.
- perf_preflight: memory, swap-in pre-check, disk (fixture dir and tempdir), sparse support, eager and mask predictions.
- perf_plan: seeded shuffle with per-scenario overrides and duration estimate.
- perf_os_cache: prewarm; Linux dd nocache drop; uncontrolled.
- perf_run_job: processx worker, 20/100 ms ps sampler, memory cap via kill_tree, timeout; cancellation helper for P10.
- --self-test and the exit-code policy.
- `tests/qualification/performance/worker.R`: New fresh-process worker. Reads request.rds (annotatr-perf-request-v1), records ps_create_time, sets .libPaths, runs library(annotatR, lib.loc=), sets options and seed, sources measure.R and scenarios.R, runs one scenario, and appends one JSON line per phase plus a startup record.
- `tests/qualification/performance/measure.R`: New. perf_phase(): proc.time, since_process_start, gc heap peak, optional Rprofmem summary, telemetry and at_read_stats deltas, cache/fd/file deltas, checks, status taxonomy including limit_refused.
Per-OS memory: macOS ps_memory_full_info maxrss; Linux /proc/self/status with clear_refs; Windows peak_wset.
Validity flags: page-ins/majflt and swap-in delta.
perf_proc_io: Linux /proc/self/io; optional macOS physical counters via macos_rusage.py.
- `tests/qualification/performance/macos_rusage.py`: New optional helper, run as python3 -I. Uses ctypes and libproc proc_pid_rusage(pid, RUSAGE_INFO_V4) to print ri_diskio_bytesread, ri_diskio_byteswritten and ri_lifetime_max_phys_footprint. No privileges or compilation needed; used only when python3 is present, otherwise fields are NA. Verified by probe rusage.py.
- `tests/qualification/performance/fixtures.R`: New deterministic generators (v1): perf_value; perf_write_envi; perf_write_speccube; perf_derive_tiff via sf::gdal_utils (strip, tile, COG, -srcwin); aniso pyramid; PNG; queues.
ROI fixture objects are built once and reused across sizes.
fixtures.json manifest: sha256, allocated bytes, vertex counts, decoded doubles of all levels, GDAL version.
perf_verify_fixture: stars RasterIO windows for ENVI/GTiff/COG and a GDAL raw VRT for SpecCube, both against the formula.
Sparse detection. No R copies of sparse files. L/XL cleanup.
- `tests/qualification/performance/scenarios.R`: New. Profiles and applicability matrix; perf_api_check of the internals used.
Scenarios P00-P14:
- P05/P07 use .app_state, .app_store, .state_init(load_project=.app_load_project), .state_load and the mod_session_server callback (.app_backup_session + .app_save_checkpoint), with autosave and queue-length variants and a testServer(.app_server) upper bound.
- P10b: at_interop_manifest, at_export_qupflowr, at_training_export.
- P14: at_control_start, .control_hub, .hub_state, at_control_stop.
Independent oracles: formula windows, layout and distinct-window byte arithmetic, centre-rule membership and means, legend-mapped mask painting, file-size hashed bytes.
- `tests/qualification/performance/summarize.R`: New. perf_read_results (jsonlite::stream_in); perf_summary_table (median, p95 for n >= 20 unflagged, MAD); perf_gates with the corrected gates listed in design H; perf_envelope; perf_compare_baseline; perf_compare_deterministic; perf_write_markdown. Writes summary.csv and summary.md.
- `tests/qualification/performance/environment.R`: New. Hardware, OS, storage, power/thermal, R, BLAS, JIT, profmem, package and native library versions, python3/libproc availability, swap and page-in pre-check, annotatR SHA, dirty diff, tarball hash, excluded untracked files, load mode and options. The home directory is redacted; output is environment.json.
- `tests/qualification/performance/README.md`: New. Usage, profiles, applicability, output schemas, cold/warm and OS-cache definitions, status taxonomy (functional vs limit vs timing), validity flags, interpretation and calibration rules. States that it succeeds window-resources.R (P02/P12).
- `tests/testthat/test-resource-bounds.R`: New mandatory-lane regression (skip_on_cran). Base-R sparse ENVI BSQ, ENVI BIP and TIVITA SpecCube fixtures with perf_value formula patches, at 512x384 vs 16384x6144, each measured in one audit_fresh() process after two in-extent warm-up reads. Asserts formula pixels, header + layout-arithmetic bytes, identical calls and read stats, heap difference <= 64 KiB, and Rprofmem max/total allocation equality and bounds. Documents the Windows dense-file fallback (8192x3072).
- `tests/qualification/window-resources.R`: No change. It reproduces the archived T15 Linux evidence. The harness README and IMPLEMENTATION.md name P02/P12 as its successors.
- `data-raw/benchmark.R`: Replace the preallocated, warm-cache micro-benchmarks with a pointer that runs tests/qualification/performance/run.R --profile quick.
- `planning/VALIDATION.md`: Rewrite 'Performance measurements and provisional targets': measurement definitions (fresh process, installed tarball build, OS-cache labels, per-OS peak memory, validity flags), gate/baseline table with gate type, status and evidence links, the documented envelope (including autosave/queue, checkpoint growth, interop/control hashing and TIFF tempdir transfer), calibration protocol and wording rules. Add test-resource-bounds.R to the core-deterministic lane.
- `planning/IMPLEMENTATION.md`: Add a T17 row with status (Phase A / Phase B), evidence links and items not verified: OME lane, macOS forced cold cache, Linux clear_refs and dd drop, Windows host and Windows CI seek-for-write.
- `planning/ROADMAP.md`: Update the status sentence. Add decision rows: reference hardware/configuration for latency gates; owner and retention policy for checkpoint generation files and O(queue) autosave; owner for full-source hashing cost in interop/control paths.
- `planning/ANALYSIS.md`: Add observations O07 (checkpoint writes every entry on every save, generation files are never removed, and autosave does this per edit) and O08 (interop/training/control paths hash full source files), each with T17 evidence and 'owner decision needed'.
- `planning/REGRESSIONS.md`: Point the 'Benchmark fixture inventory' rows to the harness fixtures and scenarios (P02, P05-P07, P10, P11, P13) and to test-resource-bounds.R.
- `planning/evidence/<date>/performance/`: New evidence directory: README.md (commands, machine, deviations), environment.json, fixtures.json, results.jsonl.gz, samples/, summary.csv, summary.md, test-resource-bounds log, and the repeatability comparison of two quick runs. Machine label instead of hostname; home directory redacted.
- `vignettes/images-and-backends.Rmd`: In 'Memory discipline', add a 'Measured envelope' subsection generated from baseline evidence: verified-up-to sizes per backend, eager k factor and tempdir transfer, known preview/navigation/export gaps, and the at_plot_image all-band read. No speed claims.
- `vignettes/shiny-workflow.Rmd`: Qualify 'materialised lazily, nothing is read from disk until you visit it': visited eager images stay in memory (known gap T16); with the control service the current entry's sources (and others up to annotatR.control_hash_max_bytes) are hashed; with autosave each edit writes a checkpoint of every entry.
- `README.Rmd`: Replace 'must fit in memory' with the measured eager-backend guidance (k x decoded doubles + base, tempdir transfer) once adopted, then regenerate README.md. List the 'whole-slide' wording for T18 claim reconciliation.
- `NEWS.md`: Development entry: performance qualification harness and window-scaling regression; measured envelope; no new support claims.

### Tests (with independent oracles)

- test-resource-bounds.R 'T17 <case>: window cost is independent of cube size' (envi-bsq, envi-bip, tivita).
- Pixel oracle: the closed-form perf_value formula, independent of annotatR.
- Byte oracle, exact: header file size (or 12 B) plus layout arithmetic (BSQ 256*4*256*2 with 1,025 calls; BIP 256*256*4*2 with 257 calls; SpecCube 256*256*4*4 with 257 calls).
- Memory oracle (metamorphic; only the cube size changes, in the same warmed process): |heap_large - heap_small| <= 64 KiB; identical binary_calls and at_read_stats(tiles, file_bytes, decoded_bytes); with profmem, alloc_max identical and <= window doubles + 64 KiB, and alloc_total difference <= 16 KiB.
- Verified by probe-bounds.R: <= 160 B heap, <= 32 B allocation, max allocation 2,097,200 B; 2.2 s installed, 7.5 s with load_all.
- test-resource-bounds.R 'T17: open is metadata-only at any size'. Oracle: open telemetry bytes equal the header file size (ENVI) or 12 bytes (SpecCube) at both sizes; window_read TRUE; handle$data NULL; object.size(img) < 64 KiB.
- test-resource-bounds.R 'T17: repeated window is a zero-byte cache hit on the large cube'. Oracle: telemetry unchanged, and the result identical to the first read, which itself equals the formula.
- Harness --self-test, fixture determinism. Generating the S fixtures twice gives identical sha256 (oracle: hash equality). perf_verify_fixture compares stars::read_stars(RasterIO=) windows for ENVI/GTiff/COG, and a GDAL raw VRT for SpecCube, with the formula; both are independent GDAL decoders.
- Harness --self-test, gate logic. Hand-built results.jsonl records (passing, failing, known gap, known gap now passing, limit_refused, memory_pressure-flagged, non-deterministic bytes) give the expected perf_gates outcomes and exit code.
- Harness repeatability. Two quick-profile runs compared with perf_compare_deterministic must give identical logical bytes, output dims, check outcomes and fixture hashes. Timing is excluded.
- P09 extraction. Phases are separated by .tile_cache_clear(). Byte oracle: sum over DISTINCT (xrange, yrange, bands) windows of independently computed centre-rule bounding boxes times layout bytes. Rectangle means equal the formula mean over independently computed member cells (tolerance 1e-9). at_extract_spectrum without a cache clear must read 0 bytes.
- P10 mask export. tiff::readTIFF(as.is=TRUE), an independent decoder, of the exported labelled TIFF equals a matrix painted from a rectangles-only project with centre-rule arithmetic. Values are mapped through the exported legend sidecar (roi_id to value), with overlap 'last' in ROI order.
- P10 cancellation. A worker killed partway through a mask_tiff export at M or L leaves no file at any receipt or target path (oracle: file.exists on the planned paths). Leftover .export-stage-* files are listed, not counted as outputs.
- P03 stale source, on an S scratch copy only (never copy sparse fixtures). After Sys.setFileTime on the header or payload, at_tile raises IMAGE_CHANGED for cached and uncached windows; at_relink_source then returns values equal to the formula.
- P03 reopen after close. Each at_tile on an at_close_image() result reads header plus window bytes (telemetry), is never a hit, and adds one cache entry; at_read_stats(closed)$tiles stays 0. Two separate opens of one file share no cache entries. Oracle: header file size plus layout arithmetic, and cache order length.
- P04 preview. Oracle: the PNG data URI decoded with png::readPNG has max(dim) <= 2048; .view_display_array output dims <= 2048. at_plot_image on M ends as limit_refused:READ_BUDGET_EXCEEDED (expected by the 1 GiB default budget, since the read is 2 GiB of doubles).
- P11 cache. Oracle: .tile_cache$bytes <= annotatR.cache_size after every put; the newest window repeat reads 0 bytes; the evicted oldest window reads layout-arithmetic bytes.
- P07 save structure. Oracles: readRDS(saved project)$image$handle is NULL; project bytes for the same reused ROI objects on S vs XL differ by <= 1 KiB; files written per checkpoint equal the number of non-NULL projects in the candidate session; cumulative projects/ files equal saves x entries (recorded as known gap G-SAVE-QUEUE).
- P05 edit with autosave. Oracle: files_written per edit equals N (non-NULL projects). Latency split into mutate+save, at_canvas and widget JSON. A testServer(.app_server) full-flush figure is reported separately as an upper bound that includes hidden mask-page outputs.
- P10b and P14 hashing. Oracle: hashed_bytes equals the sum of file.info sizes of .source_files(img, hash=FALSE) for the hashed images. A second .hub_state read for the same unchanged source does no hashing (cache keyed by path, size and mtime) and is much faster than the first.
- Harness gates G-WIN-BYTES/G-WIN-HEAP/G-WIN-RSS across S/M/L/XL in fresh workers (process maxrss on macOS, clear_refs-reset VmHWM on Linux). Oracle: the S measurement of the same sequence; spread <= 1 MiB heap and <= max(32 MiB, 25% of S) RSS.

### Acceptance

- Replace warm-cache-only conclusions with cold open, cold window, warm window, preview, edit, navigation, save, resume, extraction and export measurements. Shown by:
- Baseline-profile scenarios P01-P10, P10b, P13 and P14 in fresh workers on an installed tarball build, with since_process_start_s per phase and warm repeats in the same process.
- Edit and save measured with autosave on and off and by queue length, through the app's own state constructors and callbacks.
- data-raw/benchmark.R no longer reporting preallocated warm-cache numbers.
- summary.md with one table per workload (n, median, p95 when n >= 20 and samples are unflagged, peak memory, bytes, OS-cache label).
- Capture peak process memory and bytes read, not just elapsed time. Shown by these results.jsonl and summary.csv columns:
- Memory: maxrss_self/hwm_phase/tree_rss_peak_sampled, heap_peak, alloc_max/total.
- Bytes: logical_read_bytes/calls, hashed_bytes, written_bytes and files_written; os_read_bytes from Linux /proc/self/io or macOS physical proc_pid_rusage, with os_read_source; NA with a reason otherwise.
- Validity: pageins/memory_pressure flags.
- Record hardware, storage, versions, fixture sizes, ROI counts and cache settings. Shown by:
- environment.json: CPU, memory, swap, storage, power, R/BLAS/JIT, package and native library versions, build provenance.
- fixtures.json: logical and allocated sizes, sha256, GDAL version, ROI counts and vertex counts per geometry type.
- Per-record roi_count, roi_vertices, queue_entries, autosave, cache_size and os_page_cache fields.
- Calibrate VALIDATION.md provisional targets using representative permitted fixtures. Shown by:
- The rewritten performance table: each row has gate type, measured baseline with configuration, SHA and evidence link, and a status of adopted, not met (owner) or known gap (owner).
- Latency targets evaluated on S with n >= 20 unflagged samples on the agreed reference configuration.
- Synthetic fixtures only; permitted real fixtures recorded as blocked.
- Final adoption (Phase B) after T16.
- Benchmark artifacts are repeatable and distinguish functional failures from noisy timing. Shown by:
- Deterministic generator v1 with a sha256 manifest and independent GDAL verification.
- perf_compare_deterministic across two runs.
- A status taxonomy in which functional failures, expected limit refusals and timing are separate, and timing never fails a run.
- Advisory timing flags that need confirmation by a rerun.
- A fixed-size window does not scale memory with full cube size on a window-capable backend. Shown in CI by tests/testthat/test-resource-bounds.R (bytes, R heap and allocations; 512x384 vs 16384x6144; ENVI BSQ/BIP and TIVITA; probe-verified at <= 160 B heap and <= 32 B allocation difference). Shown at release by harness gates G-WIN-BYTES, G-WIN-HEAP and G-WIN-RSS up to 32 GiB-logical sparse and 2 GiB dense ENVI, plus 25.6 GiB-logical sparse SpecCube.
- A documented large-image envelope replaces unsupported blanket claims. Shown by:
- perf_envelope output in VALIDATION.md and a 'Measured envelope' subsection in vignettes/images-and-backends.Rmd: verified-up-to sizes, eager k factor and tempdir transfer, preview, navigation and export gaps, autosave/checkpoint and hashing costs, each with an owner.
- The README 'must fit in memory' wording replaced.
- The shiny-workflow 'nothing is read until you visit it' sentence qualified.
- DESCRIPTION/README 'whole-slide' wording handed to T18 for claim reconciliation.

### Out of scope, blocked or needing a decision

- OME-TIFF lane (P12, G-OME) is blocked here. RBioFormats is not installed (requireNamespace FALSE), and python3 3.9.6 lacks numpy and tifffile for window-resource-fixtures.py. A different fixture generator would not unblock it, because reading needs RBioFormats. The harness supports the lane where both exist (for example the Linux runner with the temporary library used for the T15 evidence). Until then the OME envelope stays unverified.
- Forcing an OS-cache-cold state on macOS needs a privileged 'sudo purge'. libproc ri_diskio_bytesread (unprivileged, via python3 ctypes) can show afterwards that a read was cold, but cannot force one. A just-written or cached file shows 0 physical bytes. macOS runs are labelled prewarm or uncontrolled. The Linux 'dd iflag=nocache count=0' drop, its read_bytes check and /proc/self/clear_refs per-phase HWM must be confirmed on a Linux runner.
- Logical (rchar-like) per-process read bytes are not available on macOS without compiled code. Only physical counters are, through proc_pid_rusage, and only optionally. Encoded bytes read by the isolated TIFF decoder (including its tempdir RDS transfer) and by the native OME reader stay NA on macOS and are best effort on Linux. This is consistent with the vignette rule that such bytes are never estimated.
- Needs a user decision: the reference hardware and configuration for latency gates. The probe machine (Apple M1, 16 GiB) had 11.4 of 12 GiB swap in use during this review and would be refused by the baseline preflight. It can run quick profiles and structural gates, but timing baselines need another machine or a quiescent session. The ROADMAP decision default applies: record a synthetic baseline first and publish no large-data speed claim.
- Needs a user decision, no current owner: retention policy for checkpoint generation files and the O(entries x ROIs) cost of every checkpoint and every autosaved edit (R/persistence.R .save_checkpoint, R/app-modules.R mod_session_server). T17 measures and records it as known gap G-SAVE-QUEUE. Fixing it belongs to a persistence follow-up (T03 owner) or T16 (bounded history and handles), to be assigned.
- Needs a user decision: an owner for full-source SHA-256 cost in the 0.2.0 interop and control paths (at_interop_manifest, at_export_qupflowr, at_training_export, and the control hub's .hub_state for the current entry). T17 measures it (about 160 MiB/s here; XL about 3.5 min) and documents it; changing hashing policy is not T17 work.
- Representative permitted real fixtures (private TIVITA data, vendor WSI/qptiff, Cubert) are external prerequisites (REGRESSIONS.md inventory). T17 calibrates on synthetic fixtures only.
- Fixing the measured gaps belongs to T16, and to T15 for any windowed TIFF/GDAL path:
- Preview reads grow with image area, and a preview is rebuilt on every edit render.
- at_plot_image reads all bands of the display level.
- Eager pixel arrays are retained in session$projects and in the app store during navigation.
- Full-size masks in mask_tiff and training exports, and export cancellation semantics.
- Eager TIFF needs about 5x the decoded doubles plus a tempdir transfer.
T17 records these as known gaps and turns them into gates after those packages land (Phase B).
- Running the performance lane on a schedule in CI requires changes to the shared CTTIR/.github workflows (T18). Only the testthat regression joins the existing mandatory lane.
- Browser-side canvas decode and draw latency (Chromium/Playwright) is not part of the R harness. P05 measures the server-side component path and a testServer upper bound; a tests/browser timing extension is optional and later.
- Windows host measurement (ps peak_wset, NTFS non-sparse fixtures) is supported by the design but not verified here (T18 host qualification). The behaviour of the testthat regression on windows-latest CI (dense 0.8-1.5 GiB writes; R's documented seek caveats on Windows) must be confirmed on its first CI run.

### Risks

- Memory pressure distorts RSS and timing. During this review: 11.4 of 12 GiB swap used and about 0.5 GB free. Mitigation: preflight of available memory and swap-ins, per-phase page-in and swap flags that exclude samples from latency gates, a memory cap with kill_tree, headroom skips for eager TIFF and masks, and a baseline that refuses to start under pressure.
- load_all/JIT noise (65-89 ms and 45 MiB for a cache hit under load_all). Mitigation: evidence only from an installed tarball build; load_all runs labelled noisy_jit and excluded from gates.
- gc max-used heap includes uncollected garbage and depends on GC history. Probe: the first two in-process measurements carry about 24 MB more heap. Mitigation: compare only symmetric sequences, use two in-extent warm-ups in the testthat regression, and never report heap as RSS.
- Sampled tree RSS misses spikes shorter than about 20-30 ms, and macOS maxrss is a lifetime value. Mitigation: phase of interest first in a fresh worker, Linux clear_refs per-phase HWM, sampled values labelled as lower bounds, and optional macOS lifetime phys_footprint.
- Sparse files: unsupported on some filesystems, and R file.copy makes them dense (probe: 16 KiB becomes 256 MiB allocated). A copy of the 32 GiB XL fixture would write 32 GiB. Mitigation: du-based sparse detection, no R copies of sparse fixtures (stale checks use S copies), and disk preflight. The testthat regression stays below 2^31 bytes per file, with per-case creation and deletion (at most 1.5 GiB transient), a Windows CI confirmation and a smaller fallback size.
- Internal API drift breaks the harness: .state_*, .app_state, .app_store, .app_backup_session, .app_save_checkpoint, .view_display_array, .materialize_project, .read_telemetry, .tile_cache, .hub_state, .control_hub. Mitigation: a perf_api_check() presence check, the quick profile in the release checklist, and the testthat regression keeping the telemetry internals exercised.
- Measurement scope of the edit workload. The component path (mutate + at_canvas + JSON) understates the app (it misses other visible outputs). testServer overstates it, because it also computes mask-page outputs a browser suspends while hidden. Mitigation: report both, labelled, and gate only the component path.
- T15/T16 change behaviour (windowed TIFF, preview cache, handle eviction, export streaming). Mitigation: gates and applicability driven by at_image_capabilities(); known_gap_now_passing reporting; re-baseline after each change; flag registry vs per-image capability mismatches (ometiff today).
- Timing variance from thermal, battery or background load. Mitigation: record pmset and load average, require AC power for evidence, randomize job order, use repetitions, keep timing flags advisory with rerun confirmation, and put no timing gates in mandatory CI.
- Long runs and disk use. Baseline is re-estimated at 45-60 min plus fixtures; XL hashing takes about 3.5 min per run; L previews take tens of seconds each. Mitigation: per-scenario rep overrides, XL hashing only with --hash-xl or in release, fixture cache reuse, L/XL cleanup, disk preflight including tempdir.
- The working tree changes while a run is in progress (observed during this review: another process edited tracked files and IMPLEMENTATION.md announces a rebase onto 288c1c5). Mitigation: snapshot tracked sources with git ls-files before the build, record the diff hash at start and end, and refuse evidence mode when they differ.
- GDAL COG layout and overview differences across versions change fixture hashes. Mitigation: GDAL version in the manifest; correctness checked against the formula, not cross-machine hashes.
- Native aborts (T18a class) in workers that mix in-process tiff writes and magick encoding (TIFF reads are already isolated). Mitigation: per-job process isolation; the orchestrator records the abort with a stderr tail and continues.
- Path and host leakage in published evidence. Mitigation: machine label instead of hostname, home directory redacted to ~, fixture paths stored relative to the fixture root.

### Depends on

- T15
- T16

## T18: Enforce CI and qualify releases (annotatR main @ 649cf49, version 0.2.0 development). Corrected after a skeptical review against the code, the roadmap and VALIDATION.md.

Estimated effort: 40 focused hours.

### Current state

REVIEW BASIS
- Claims about code are checked against HEAD 649cf49 with `git show` and `git ls-tree`.
- Review probes are under <scratch>
  - lintdetail.R with the lp/ tree
  - nolintpkg/
  - iw-noome.R
  - fixture-manifests.R
  - backend-capabilities.R
- The submitted spec's probes are in scope/t18/.
- During this review another process (not this reviewer) changed the working tree:
  - Untracked: .gitattributes (`tests/testthat/fixtures/** -text`, `tests/fixtures/** -text`) and tests/testthat/test-export-contract.R (byte-identical to 16ddb1d).
  - Modified: NEWS.md, cran-comments.md, R/interop-capabilities.R:7 and R/interop-handoff.R:921 (comments only), the analytical fixture manifests, planning/ROADMAP.md, planning/IMPLEMENTATION.md and planning/evidence/2026-10-18/*.
  - The planning edits announce a re-commit of the port: 'rebased onto 288c1c5 and committed as @CODE@', 81 files / 827 tests / 4969 expectations, house lint 58.
  - Every number below is for 649cf49. Re-measure on the commit that actually lands.

VERIFIED AS SUBMITTED (kept)
- Branch and release state:
  - origin/main = 288c1c5 (gh api).
  - 0ce8cee and 649cf49 are unpushed.
  - Branch protection returns 404; rulesets are [].
  - No tags and no GitHub releases.
- Caller workflows:
  - lint.yaml: `blocking: false`.
  - test-coverage.yaml: `floor: 0` and `secrets: inherit`.
  - R-CMD-check.yaml: no inputs.
  - pkgdown.yaml: a local workflow.
- Shared CTTIR/.github:
  - main = f7acf58. The scratch copies match it byte for byte (git hash-object).
  - The lint, coverage and check contracts are as described.
  - check-r-package sets `_R_CHECK_CRAN_INCOMING_=false` only when it is unset, uses `error_on='warning'`, and prints testthat.Rout in 'Show testthat output' even on success (run 38549112441).
- Check-run names, verified from runs 38549112441, 38549112309 and 38549112203:
  - 'R-CMD-check / macOS-latest (release)'
  - 'R-CMD-check / windows-latest (release)'
  - 'R-CMD-check / ubuntu-latest (release|devel|oldrel-1|oldrel-3)'
  - 'lint / lint'
  - 'test-coverage / test-coverage'
- Last CI run (03ce6aa):
  - Everything is green except oldrel-3, where pak::repo_status shows Bioc 3.18 unavailable.
  - B_tests = 89.03%.
  - Lint notice: '3 lint findings: cttir_quiet=3'.
  - RBioFormats 1.12.0 loads on macOS, Windows and Ubuntu release/devel/oldrel-1 (the test-backend-optional.R:13 skip fires on each).
- House lint at 649cf49 = 53:
  - R: 1; inst: 5; vignettes: 4.
  - tests/testthat: 16 (4 `verbose = FALSE` and 12 `stop()` doubles).
  - Standalone drivers: 27 (qualification 23, browser 3, audit 1).
  - There is no .lintr; `^\.lintr$` is already in .Rbuildignore.
- Coverage: 90.59% (covr type='tests', clean export, no RBioFormats), per-file tail as listed; 91.44% if the 103 RBioFormats-only lines run.
- Timing figures are indicative only.
- There are 9 `skip_on_os('windows')` sites:
  - test-control-protocol.R:518 and 568
  - test-control-http.R:75
  - test-interop-utils.R:65 and 152
  - test-io-project.R:156
  - test-interop-handoff.R:158 and 471
  - test-training.R:290
- sf defect, reproduced again on the installed HEAD build (t18/lib-head):
  - Symptom: in a fresh process, library(annotatR) → at_load_project() → at_rois() fails with 'no applicable method for st_geometry applied to an object of class "list"'; sf is not loaded.
  - With importFrom(sf, st_sfc) (lib-sffix), at_rois() returns 1 row.
  - Cause: R/utils.R:.rois_to_tbl line 216 uses do.call(c, ...). NAMESPACE imports only rlang and stats; sf appears only in the delayed S3method(sf::st_as_sf/st_geometry, annot_roi) lines 32-33.
  - The ENVI/TIVITA reopen part of installed-windows.R fails at HEAD and passes with the fix (review-t18/iw-noome.R).
- Node: 48 of 48 pass (node v26.12.0). A24 and A31 have no testthat-named test.
- Metadata drift as listed. A local --as-cran check fails only on the CRAN incoming name-conflict ERROR.

CORRECTIONS TO THE SUBMITTED STATE
1. The lint waiver does not work as claimed.
   - lintr 3.4.0 `lintr:::normalize_exclusions` expands a directory entry into whole-file `list(Inf)` exclusions and drops the per-linter value.
   - Probe: with the submitted .lintr, injected `function(verbose = TRUE)` lines in tests/browser and tests/qualification were NOT reported. Without .lintr they were.
   - So the submitted .lintr silently waives every house rule for those directories, including future files.
   - Two forms are verified to waive only cttir_condition (cttir_quiet still fires):
     - Per-FILE entries such as `"tests/browser/minimal-app.R" = list(cttir_condition = Inf)`.
     - `# nolint start: cttir_condition.` … `# nolint end` blocks.
   - Precedent: R/io-tiff-process.R already uses inline `# nolint: cttir_condition.` with a reason.
2. Gap (d) is wrong.
   - Pre-port Windows CI already ran cross-process tests: test-tiff-process.R (callr) and test-control-http.R (callr::r_bg up to line 75).
   - At HEAD, the ported audit_fresh tests have no Windows skip and will run on windows-latest on the first post-port run (helper-fresh-process.R:audit_fresh): test-audit-persistence.R A01/A07, test-persistence-contract.R, test-persistence-legacy.R:60 and test-identity.R.
   - test-persistence-contract.R 'atomic writes roll back checked Unix and Windows replacement failures' already injects failures portably for platform='windows' (R/persistence.R:.atomic_save_rds, rename/writer arguments).
   - What is actually missing is the installed-windows.R scenario:
     - at_rois() as the FIRST call (the existing tests call at_add_roi first, which loads sf and masks the defect);
     - zero decoded bytes on reopen;
     - ENVI/TIVITA/OME windows;
     - close/reopen.
3. 'NEWS 0.0.1 documents the 0.1.0 Zenodo release' is unsupported.
   - The CITATION.cff:7 DOI 10.5281/zenodo.21889921 returns 404 at doi.org, the DataCite API and zenodo.org (2026-10-18).
   - .zenodo.json says 'Prepared draft. Not yet published.'
   - The 0.0.1 heading corresponds to DESCRIPTION 0.1.0 at f69bf20 (O04).
4. test-io-project.R:67 cannot just use fresh_loader(). Its callr child calls the internal .all_roi_ids(), which is not visible after library() in installed mode. Use audit_fresh(), which evaluates in a child of asNamespace('annotatR').
5. PK-4 cannot run here. The `_pkgdown.yml` template is themakR (Config/Needs/website: CTTIR/themakR), and themakR is not installed. The evidence available is the CI pkgdown run (38549111300, success).
6. Pinning and the shinytest2 lane are not shared-only.
   - A caller can use `uses: …@<sha>` plus the existing lint input `config-ref`. This contradicts the 'move together' comment in .github/workflows/R-CMD-check.yaml, so it is a policy decision.
   - The shinytest2 browser lane can be enabled package-locally on GitHub runners, which have Chrome.
   - Only the Playwright runners need workflow steps.
7. Shared CI changes are not out of scope. ROADMAP T18 and its decision table say to route them through CTTIR/.github and record them as a dependency.

ADDITIONAL GAPS
8. A closure-map link is dead.
   - planning/IMPLEMENTATION.md links tests/testthat/test-export-contract.R (A22/A31), but the file is not in 649cf49.
   - It is on 16ddb1d (12 tests) and is the only roadmap test file that was not ported. That explains most of R/export-policy.R's 76.6%.
   - The concurrent restore adds 5 `stop()` doubles (lines 18, 29, 81, 86, 93), so house lint becomes 58.
9. There is no .gitattributes at HEAD.
   - The byte-pinned text fixtures are LF-only and hash-pinned:
     - analytical .json, .geojson and cube.hdr (MD5SUMS);
     - the readers .hdr files (sha256.json).
   - A Git-for-Windows checkout with the usual `core.autocrlf=true` would convert them, and test-analytical-reference.R:161 (the MD5 check) would fail on windows-latest. This is inferred, not seen in logs.
   - All 6 manifests (114 entries) match locally (fixture-manifests.R). Only the analytical MD5SUMS is checked by a test.
10. Capability claims do not match.
    - at_backend_list() reports ometiff as metadata_only FALSE, window_read FALSE, 'unqualified', 'eager' (R/zzz.R:.register_backends).
    - R/backend-tiff.R:.ometiff_read sets per-image .window_capabilities('native'), i.e. TRUE / TRUE / raw-scalar-v1.
    - README.Rmd and vignettes/images-and-backends.Rmd:108 claim OME window reads.
    - README lists qptiff, but the vignette (lines 117-118) says no vendor/qptiff layout is qualified.
    - R/zzz.R's 0% is not only .onLoad: .register_backends() and .backend_capabilities() are plain functions.
11. The registry matching is weak.
    - A25's only CI-run testthat match is a static grep (test-widget-canvas.R:229).
    - A33 is matched only by 0.2.0 interop analogues (test-interop-handoff.R:582, test-interop-manifest.R:158). test-provenance-keys.R, the closure-map file, carries no IDs.
    - A27 runs only where RBioFormats loads.
    - Matching parse()d descriptions cannot show that a test executed rather than skipped.
12. The inverse skips at test-backend-optional.R:6 and 13 appear in every CI skip list, and test-audit-app.R:318 is a vestigial skip (.save_checkpoint exists).
13. Version references:
    - R/interop-capabilities.R:7 and R/interop-handoff.R:921 hard-code 0.2.1.
    - pkgdown 2.2.1 dev_mode_auto('0.2.0') = 'release' (verified), so pushing 0.2.0 deploys the development docs to the release site root.
14. Not available locally: Java, RBioFormats, LaTeX, gs, qpdf, numpy, themakR, and any secret scanner. tests/fixtures/legacy-f69bf20/generate.R needs /tmp/annotatr-roadmap-baseline-source, but its bytes are pinned.

GAPS AGAINST T18 ACCEPTANCE
- (a) Lint and coverage are report-only.
- (b) The node tests run in no CI lane, and real-browser A24/A25 evidence is local only.
- (c) The io-project fresh-process test skips under check and covr.
- (d) The installed reopen scenario is absent, and Windows has never run the port.
- (e) The sf import defect.
- (f) Skips are unclassified, and core Suggests can skip silently.
- (g) Metadata and claims drift: version, DOI, OME capability, qptiff.
- (h) R (>= 4.1.0) is unverified; CI only verifies 4.5 and later.
- (i) The incoming ERROR is hidden in CI.
- (j) Planning links and placeholders are unchecked.
- (k) No protection on main, and direct pushes are allowed.

### Design

Gates are switched on only after a green CI run of the exact commit. Every count is re-derived on the commit that lands.

S0 Baseline on a pull request
- Wait for the concurrent re-commit and confirm `git ls-files .gitattributes tests/testthat/test-export-contract.R`.
- Decide the development version before main receives the port. 0.2.0.9000 keeps the pkgdown site under /dev; with 0.2.0, a push overwrites the release site.
- The maintainer pushes a branch and opens a PR to main. All three workflows run on pull_request; pkgdown builds but does not deploy.
- Archive into planning/evidence/<date>/ci/: the per-OS 'Show testthat output', Status and NOTE lines, the skip lists, B_tests and the lint notice (58 expected).
- Fix, or mark unverified in the README, any failure in the first-run risks: OME on RBioFormats runners, Windows fresh-process tests, and CRLF fixtures if .gitattributes is missing.

S1 Lint baseline, then blocking
(a) at_fix_geometry signature
- Recommended: `at_fix_geometry(project, verbose = NULL, call = rlang::caller_env(), quiet = FALSE)`.
- Positional verbose (2nd) and call (3rd) keep working, so no dots shim is needed and nothing breaks.
- When `!is.null(verbose)`:
  - `.check_flag(verbose)`;
  - abort with at_validation_error if quiet is also supplied;
  - `cli::cli_warn(..., class = c('at_deprecated_warning', 'at_warning'), .frequency = 'regularly', .frequency_id = 'annotatR-at_fix_geometry-verbose')`;
  - `quiet <- !verbose`.
- Otherwise `.check_flag(quiet)`.
- Guard the message with `if (!quiet) cli::cli_inform(...)`.
- The roxygen text must not contain the literal pattern the linter matches.
- Alternatives:
  - The submitted dots form, if `call` must stay last; it breaks a positional `call`.
  - Minimal: keep verbose and add `# nolint: cttir_quiet.` at R/geometry.R:695 with a reason.

(b) Tests for the transition
- The four call sites become `quiet = TRUE`.
- New test-quiet-transition.R, with `# nolint: cttir_quiet.` on the deprecated lines.

(c) Condition calls
- Convert every `stop()` test double in tests/testthat to `cli::cli_abort()`: 12 at 649cf49, 17 after the restore.
- Convert the 5 `stop()` calls in inst/examples/reproducible-analysis.R.
- In the vignette, the 4 `stopifnot()` calls become 3 `if (!...) cli::cli_abort(...)` guards.

(d) Driver waiver, scoped to cttir_condition
- Option 1: a root .lintr with per-FILE entries, for example `"tests/qualification/qupath-roundtrip.R" = list(cttir_condition = Inf)` for each driver, plus 'tests/testthat.R' and 'data-raw', encoding UTF-8, and no `linters:` field.
- Option 2: `# nolint start: cttir_condition.` / `# nolint end` blocks inside each driver.
- Both are verified. Never use directory entries.
- New driver files are linted in full. Drop the installed-windows.R entry when that file is deleted.

(e) Set `blocking: true` in lint.yaml in the same commit.

S2 Coverage floor
- Floor = trunc(min(clean-export value, first green post-port CI B_tests)) on the landed commit; 90 is expected. Restoring test-export-contract.R only raises it.
- A comment in test-coverage.yaml records the baselines and the ratchet rule: at each release, trunc(min of the last three green runs).
- Negative control: a throwaway draft PR with `floor: 99` must turn 'test-coverage / test-coverage' red with '::error::Coverage … below the floor'. Record the run id and close the PR unmerged.
- Only line coverage is available. The ledger reports per-file coverage for audited files.

S3 Package-local CI regressions
(a) sf import
- Add `#' @importFrom sf st_sfc` to R/annotatR-package.R, giving `importFrom(sf,st_sfc)` in NAMESPACE.
- Register a new finding (proposed A34; ID to be confirmed) in ADDITIONAL-FINDINGS.md, with the failing-before output from iw-noome.R and t18/sf-lazy-repro.R.
- Add a NEWS entry.

(b) test-installed-reopen.R
- Uses audit_fresh() twice: one process saves, a fresh one loads.
- ENVI and TIVITA always; OME when RBioFormats and xml2 are present, with java.parameters set.
- The second process calls at_rois() FIRST.
- Asserts:
  - decoded_bytes == 0;
  - handle data and levels are NULL;
  - the saved ROI ids;
  - literal windows c(322,332,323,333) and c(122,132,123,133);
  - close/reopen gives an identical window;
  - 'sf' %in% names(getNamespaceImports('annotatR')).
- The behavioural check bites only in installed mode (R CMD check and covr); under load_all, pkgload loads every DESCRIPTION Import.
- Then delete tests/qualification/installed-windows.R.

(c) test-io-project.R
- Line 67 is rewritten with audit_fresh().
- Line 156 stays an injection-technique skip and points to the portable Windows rollback test.

(d) Node lane
- Move the two JS tests to tests/testthat/js/.
- Asset root: `process.env.ANNOTATR_INST_DIR || path.join(__dirname, '../../../inst')`.
- test-widget-node.R:
  - `skip_on_cran()`;
  - `withr::local_envvar(ANNOTATR_INST_DIR = system.file(package = 'annotatR'))`;
  - `system2(node, c('--test', shQuote(files)))`, expecting status 0.
- Update the paths in:
  - test-widget-canvas.R:226 and widget.test.js:1;
  - tests/browser/README.md:37;
  - IMPLEMENTATION.md:57;
  - the current commands in REGRESSIONS.md. Its historical tables keep the old paths with a note.

(e) Audit registry
- CSV columns: finding, work_package, lane (testthat | node | browser-local | qualification-local), file, test_pattern, capability, implementing_revision, failing_before_evidence, reviewer_date.
- test-audit-registry.R requires:
  - the IDs to include A01–A33 and to match `^A\d{2}$`;
  - each testthat or node row's file to exist and contain a description matching test_pattern.
- Bind IDs to the closure-map files:
  - add 'A33' prefixes in test-provenance-keys.R;
  - add 'A31' prefixes in test-qupath-native.R;
  - A22 → test-export-contract.R and test-audit-persistence.R;
  - A24/A25 → node and browser-local.
- This is presence only. Execution is shown by the ledger's ListReporter run and by the CI UNVERIFIED summary.

(f) Capability skips
- `skip_unverified(capability, why, detail)`, where why is one of not-installed, fixture-unavailable, not-supported, opt-in or not-applicable.
- Classify every ad-hoc skip:
  - the OME, CUVIS, TIVITA, NPY and browser lanes;
  - the 9 Windows sites;
  - test-io-project.R:163, test-shiny-app.R:11, test-reproducible-analysis.R:8;
  - test-backend-optional.R:6/13 (or simulate absence by temporary re-registration);
  - remove the vestigial test-audit-app.R:318.
- setup-capabilities.R prints the full block and ONE aggregated `::notice title=annotatR unverified capabilities::` line, because GitHub caps annotations per step and job.
- Symlink tests: try `file.symlink()` first and skip as not-supported only if it fails. Hosted Windows runners run as an administrator.
- The Windows 0600 token check is 'unverified on Windows' unless the docs restrict the control service to POSIX.

(g) CI-required capability guard
- New test-ci-capabilities.R, active only when GITHUB_ACTIONS=='true' and GITHUB_REPOSITORY=='CTTIR/annotatR'; ANNOTATR_CI_OPTIONAL can relax it.
- It fails if node, or any of these core Suggests, is missing: tiff, magick, shiny, shinyjs, htmlwidgets, bslib, callr, pkgload, httpuv, later, curl, withr, xml2, png, terra, zip.
- RBioFormats stays skip_unverified. The ledger requires OME to have run on at least one CI OS before the README keeps the OME row.

(h) test-capability-claims.R
- For envi and tivita (fixtures/readers/binary), and ometiff when available, at_image_capabilities() equals the at_backend_list() row and a literal claims table.
- Fix the ometiff entry in R/zzz.R:.register_backends to `.backend_capabilities(TRUE, TRUE, 'raw-scalar-v1', 'native')`, or hand it to the T15 remainder.

(i) test-fixture-integrity.R checks all sha256.json and SHA256SUMS manifests on every OS using digest.

(j) Optional decision: auto-enable the shinytest2 lane when on GitHub Linux with chromote::find_chrome(); check it is stable on the PR.

S4 Release qualification
- planning/RELEASE.md and tests/qualification/release-gates.csv as submitted.
- RELEASE.md also records:
  - supported browsers: Chrome headless shell 156 (chromote 0.5.1) and Playwright 1.64.1;
  - that O06 is already stated in vignettes/shiny-workflow.Rmd:107;
  - that the O06 history and dependency scan is unverified.
- release-ledger.R as submitted, plus:
  - an output directory outside the repo, or excluded from the dirty-tree check;
  - the CTTIR/.github sha it used;
  - NOTE and WARNING lines;
  - node_modules/ and package*.json added to the forbidden paths;
  - a ListReporter run to show each registry row executed;
  - a per-file coverage report;
  - PK-4 taken from the CI pkgdown run.
- release-metadata.R as submitted, plus:
  - the DOI resolves, or is absent;
  - no '@CODE@' placeholders remain;
  - every relative link in planning/*.md resolves;
  - no hard-coded future versions in R/ or vignettes/;
  - the README capability sentences agree with at_backend_list().
- Checklist corrections:

| Item | Corrected entry |
|---|---|
| ST-9 | Fails at HEAD (ometiff capabilities, qptiff row) |
| PK-4 | Not local; taken from CI |
| ST-6 | windows-latest: audit_fresh tests plus test-installed-reopen.R |
| ST-7 | Runs in CI via S3(i) |
| ST-3 | A24/A25 real-browser evidence is required |
| ST-13 (new) | Planning links and placeholders |

S5 Required checks (admin)
- Require:
  - R-CMD-check on macOS, windows and ubuntu (release) and ubuntu (oldrel-1);
  - 'lint / lint';
  - 'test-coverage / test-coverage'.
- Recommend devel, oldrel-3 and pkgdown stay informational.
- Require PRs, with no bypass.
- Record that the required check names are coupled to the shared matrix labels.

Shared-CI dependency proposals (recorded, not executed)
- Upload artifacts and JUnit results on success.
- Inputs for optional lanes (node, browser, Playwright).
- Handling of the oldrel-3 Bioconductor mirror failure.
- A pinning policy.
- Per-file coverage.

### Files

- `.github/workflows/lint.yaml`: `blocking: true` after the green PR baseline. The comment states the house count of 0 at <sha> and that the waiver is per-file cttir_condition only.
- `.github/workflows/test-coverage.yaml`: `floor:` recomputed on the landed commit (90 expected). The comment records the local and CI baselines and the ratchet rule.
- `.lintr`: New file. Holds exclusions only: 'tests/testthat.R', 'data-raw', and per-FILE `list(cttir_condition = Inf)` entries for each driver in tests/qualification, tests/browser and tests/audit. Encoding UTF-8; no `linters:` field. Never directory entries: lintr 3.4.0 turns those into whole-file waivers for every linter (probe verified). Alternative: nolint blocks in the drivers.
- `tests/qualification/*.R, tests/browser/minimal-app.R, tests/audit/run-regressions.R`: Only for the nolint variant: `# nolint start: cttir_condition.` / `# nolint end` around the stopifnot oracles.
- `R/geometry.R`: at_fix_geometry(project, verbose = NULL, call = rlang::caller_env(), quiet = FALSE), keeping positional compatibility. Classed, frequency-limited deprecation warning; error when both arguments are given. The roxygen text avoids the pattern the linter matches.
- `R/utils-check.R`: Optional .resolve_quiet() helper only if it is reused. No dots handling.
- `R/annotatR-package.R, NAMESPACE`: `#' @importFrom sf st_sfc` and the regenerated importFrom(sf,st_sfc).
- `man/at_fix_geometry.Rd`: Regenerated with roxygen2 8.0.0.
- `R/zzz.R`: The ometiff registration uses .backend_capabilities(TRUE, TRUE, 'raw-scalar-v1', 'native'), matching .ometiff_read (or this goes to the T15 remainder).
- `tests/testthat/test-geometry.R, tests/testthat/test-refine-correctness.R`: `verbose = FALSE` becomes `quiet = TRUE` (lines 118, 229 and 240; line 48).
- `tests/testthat/test-quiet-transition.R`: New. Covers the deprecated verbose by name and by position, a positional `call`, conflicts and invalid flags. Deprecated lines carry `# nolint: cttir_quiet.`
- `tests/testthat/test-app-capabilities.R, test-app-modules-extra.R, test-audit-app.R, test-batch.R, test-control-protocol.R, test-persistence-contract.R, test-persistence-source.R, test-shiny-modules.R, test-training.R, test-widget-canvas.R, test-export-contract.R`: `stop()` test doubles become `cli::cli_abort()`: 12, plus 5 in the restored test-export-contract.R.
- `inst/examples/reproducible-analysis.R, vignettes/reproducible-analysis.Rmd`: cli_abort replaces the 5 stop() calls; 3 guards replace the 4 stopifnot() calls.
- `tests/testthat/helper-capabilities.R, tests/testthat/setup-capabilities.R`: New. skip_unverified() and the run summary, with one aggregated ::notice line.
- `tests/testthat/test-ci-capabilities.R`: New CI-required guard, scoped to GITHUB_ACTIONS and GITHUB_REPOSITORY.
- `tests/testthat/test-capability-claims.R`: New. Checks at_image_capabilities() against at_backend_list() and a literal claims table for envi, tivita and ometiff.
- `tests/testthat/test-fixture-integrity.R`: New. Checks the sha256 manifests (readers, windows, mask-raster) with digest.
- `tests/testthat/test-reader-correctness.R, test-windowed-readers.R, test-backend-cuvis-sdk.R, test-backend-tivita.R, test-io-npy.R, test-app-browser.R, test-widget-canvas.R, test-control-http.R, test-control-protocol.R, test-interop-handoff.R, test-interop-utils.R, test-training.R, test-shiny-app.R, test-reproducible-analysis.R, test-backend-optional.R, test-audit-app.R`: Classified skip_unverified calls. Symlink tests probe file.symlink() first. The inverse OME/CUVIS skips become not-applicable (or simulate absence). The vestigial skip at test-audit-app.R:318 is removed.
- `tests/testthat/test-io-project.R`: Line 67 is rewritten with audit_fresh(). Line 156 is classified as an injection-technique skip that points to the portable rollback test.
- `tests/testthat/test-installed-reopen.R`: New. Two audit_fresh() processes, with at_rois() called first. Asserts literal windows, zero decoded bytes and close/reopen; OME is conditional; checks that sf is an import.
- `tests/qualification/installed-windows.R`: Delete, and remove its .lintr entry and its references in IMPLEMENTATION.md.
- `tests/testthat/js/widget.test.js, tests/testthat/js/keyboard.test.js`: Moved from tests/audit/. Asset root is ANNOTATR_INST_DIR, falling back to ../../../inst.
- `tests/testthat/test-widget-node.R`: New node:test runner. Expects status 0; skip_unverified when node is missing, but the CI guard fails in that case.
- `tests/testthat/fixtures/audit-registry.csv, tests/testthat/test-audit-registry.R`: New registry with the expanded columns, bound to the closure-map files. It is a presence oracle only.
- `tests/testthat/test-qupath-native.R, tests/testthat/test-provenance-keys.R`: Prefix the test descriptions with A31 and A33 respectively. Snapshots exist only for test-errors.R, so this is safe.
- `.gitattributes, tests/testthat/test-export-contract.R`: Concurrent work: make sure both are committed before the baseline (fixtures `-text`; the export contract tests from 16ddb1d).
- `tests/qualification/release-gates.csv, release-ledger.R, release-metadata.R`: New, with the S4 additions: DOI, links, placeholders, capability claims, NOTE lines, execution check and forbidden paths.
- `planning/RELEASE.md`: New checklist, ratchet procedure, required checks, browser versions and unverified configurations.
- `planning/ADDITIONAL-FINDINGS.md`: Record the sf import finding (proposed A34) with failing-before and passing-after evidence.
- `planning/IMPLEMENTATION.md, ROADMAP.md, ANALYSIS.md, REGRESSIONS.md, tests/browser/README.md`: T18 status, O03/O06 closure, node paths, links, and resolve the '@CODE@' placeholders.
- `NEWS.md`: Entries for the quiet deprecation, the sf import fix and the ometiff capability correction. Rename the 0.0.1 heading to 0.1.0.
- `README.Rmd, README.md`: O06 sentence, OME window claim matching at_backend_list(), qptiff footnote, CI-only/unverified footnotes, browser statement. Re-render.
- `DESCRIPTION, CITATION.cff, .zenodo.json, cran-comments.md`: Version 0.2.0.9000 before pushing to main (decision). Remove or fix the unresolvable DOI. Release-time version and date.
- `planning/evidence/<date>/`: Ledger outputs and CI logs per OS.

### Tests (with independent oracles)

- test-quiet-transition.R
- Oracle: whether the 'Repaired' message appears; the geometry equals the quiet=TRUE reference.
- Checks at_deprecated_warning by name and by position (rlib_warning_verbosity='verbose').
- A positional `call` still works.
- at_validation_error for quiet=NA and for both arguments supplied.
- House lint
- Oracle: 0 lints with the shared cttir_linters() and the corrected .lintr.
- Negative controls, run locally and as a CI PR:
  - `verbose = FALSE` in a testthat file turns lint red;
  - `function(verbose = TRUE)` in tests/browser/*.R is still reported (proves the waiver is limited to cttir_condition);
  - a new tests/qualification file with stop() is reported.
- sf import
- Structural oracle: getNamespaceImports includes sf (true in both load modes).
- Behavioural oracle: a fresh library(annotatR) process runs at_load_project() then at_rois() first and gets the saved IDs. This only bites in installed mode.
- Negative control: a CI PR reverting the import fails all R-CMD-check jobs.
- test-installed-reopen.R
- Oracle: the fixture formula 100*(band+1)+10*(y+1)+x+1 (literal windows).
- Also: ROI ids saved by process 1, decoded_bytes==0, NULL handle, identical window after close.
- ENVI and TIVITA pass with the fix and fail at HEAD (iw-noome.R).
- test-widget-node.R
- Oracle: node:test exit status over 48 independent cases against the installed assets.
- Negative control: reverting the even-odd hole logic fails A24.
- test-audit-registry.R
- Oracle: the CSV registry against parse() descriptions and JS test names in the bound files.
- Fails if an ID is dropped, a bound file is missing, or a test_pattern has no match (for example, removing the A33 prefixes).
- Execution is not proven here.
- Registry execution (ledger)
- Oracle: a testthat ListReporter run on the export; each testthat and node row needs at least one passed, unskipped test.
- OME rows come from the CI per-OS logs.
- test-io-project.R fresh process
- Oracle: the tile is identical to the in-process value and there is one ROI id.
- The test is absent from the CI skip lists.
- Capability visibility
- The check-reporter output contains 'UNVERIFIED <capability> (<why>)' lines and a single aggregated ::notice.
- The ledger fails on unclassified skips.
- test-ci-capabilities.R
- Oracle: requireNamespace() and Sys.which('node') on CI.
- Negative control: requiring a nonexistent package through the env variable fails.
- test-capability-claims.R
- Oracle: a literal claims table transcribed from the README and vignette.
- Fails at HEAD for ometiff (FALSE/FALSE against claimed TRUE/TRUE) and passes after the R/zzz.R fix.
- test-fixture-integrity.R
- Oracle: the manifests written by the independent NumPy/tifffile generators; 114 entries match here.
- Negative control: converting one .hdr to CRLF fails.
- Coverage gate
- Oracle: the shared workflow's explicit exit.
- Negative control: a CI PR with floor: 99 goes red, with the run id recorded.
- release-metadata.R
- Oracles:
  - the DESCRIPTION, NEWS, CITATION and .zenodo texts;
  - the DOI's HTTP status;
  - planning links resolving and no '@CODE@' placeholders;
  - future-version grep;
  - the README re-rendered with no diff;
  - README claims against at_backend_list().
- It must currently report: CITATION/.zenodo at 0.1.0, 0.2.0 under a development heading, the DOI 404, and the 0.2.1 comments.
- release-ledger.R build check
- Oracle: the tar listing against the forbidden list (planning/, data-raw/, tests/{audit,browser,qualification}, hsi-workbench, docs/, node_modules, package*.json).
- Records the Status line, NOTE and WARNING lines, and the tarball sha256.
- A skip is never recorded as 'verified'.

### Acceptance

- Required checks fail for regressions.
- Lint is blocking, the coverage floor is enforced, and R CMD check runs the new regressions.
- Shown by green runs plus CI negative-control PR runs (lint, floor: 99, sf revert) with recorded run IDs.
- Only partly met until S5 branch protection and PR-only merges are in place.
- Coverage baseline measured, not invented: local and first post-port CI values, recomputed on the landed commit, plus a ratchet rule. Restoring test-export-contract.R is accounted for.
- Regressions for audited paths.
- The registry binds A01–A33 (plus A34 if registered) to their closure-map files.
- The ledger shows they executed.
- A24/A25 run in CI through node and have real-browser evidence locally.
- Planning links resolve.
- Lint blocking after the chosen baseline. The waiver is limited to cttir_condition in named driver files, shown by the negative controls.
- Missing optional formats are visible.
- Per-OS UNVERIFIED summaries.
- The CI guard stops core lanes from skipping silently.
- OME is claimed only if it ran on at least one CI OS.
- The ledger never marks a skip as verified.
- Package checks with examples, vignettes and optional dependencies run in CI (error on warnings) and in the ledger's --as-cran run. NOTEs are reviewed. Browser and interop lanes are qualified separately, each with its host.
- Build from the tracked source: a fresh checkout in CI and a git-archive export in the ledger, with the forbidden-path assertion.
- NEWS, DESCRIPTION, README, generated README and support tables aligned.
- release-metadata.R passes.
- The capability claims test passes.
- qptiff is footnoted.
- The DOI is resolvable or removed.
- The version decision is applied and the pkgdown mode is consistent.
- Every release claim maps to a 'verified' ledger item, or is reworded or marked unverified.
- Windows-host persistence.
- windows-latest runs the audit_fresh persistence tests, test-installed-reopen.R (OME where RBioFormats loads) and the portable rollback test.
- Skips are labelled.
- A desktop Windows host stays unverified.
- Authorship and publication rules are preserved.

### Out of scope, blocked or needing a decision

- Shared CTTIR/.github changes: recorded as dependency proposals (success artifacts, optional-lane inputs, oldrel-3 Bioconductor handling, pinning policy, per-file coverage). They are not executed and not needed for acceptance.
- Pinning the shared workflows is technically possible in the caller (`@<sha>` plus config-ref) but goes against the estate's move-together policy, so it is a maintainer decision.
- Branch protection and rulesets need admin rights; this is a maintainer action.
- Pushing is a maintainer action. It must wait for the concurrent re-commit (the '@CODE@' placeholders, the restored test file and .gitattributes) and must go through a PR first.
- Not verifiable here:
- OME via RBioFormats (no Java);
- window-resources.R (Linux only);
- a desktop Windows host;
- the CUVIS SDK;
- private TIVITA data;
- QuPath 0.7.0;
- NumPy/tifffile (fixture generation and decoders);
- non-Chromium browsers;
- the PDF manual (no LaTeX);
- a pkgdown build with themakR;
- the O06 secret and history scan;
- R versions below 4.5;
- legacy fixture regeneration.
- EX-7 (streaming export) and EX-8 (performance) are blocked on T16 and T17.
- Decisions for the user:
- The version: 0.2.0.9000 now; 0.2.1 or 0.3.0 at release (also affects the interop comments and the pkgdown mode).
- The quiet transition or a one-line waiver; when to remove verbose.
- The R minimum.
- The CRAN name conflict.
- Publishing or removing the DOI.
- The waiver form: per-file entries, nolint blocks, or converting the 27 calls.
- Whether devel is a required check.
- The shinytest2 lane in CI.
- The ID for the sf finding.
- Tagging, releases, Zenodo deposits, commits and pushes are not part of T18.
- T18a: results are only recorded. Second-audit IDs are optional in the registry.

### Risks

- Concurrent edits are re-committing the port. The counts drift (lint 53→58, tests 815→827), and the scratch patches target 649cf49, so regenerate them on the landed commit.
- The first CI run of the port may fail: OME on RBioFormats runners, the Windows fresh-process tests, and CRLF fixtures if .gitattributes is missing.
- Coverage depends on the environment (about 0.85 points from RBioFormats). Bioconductor outages can drop it.
- With the workflows unpinned at @main, a new shared rule turns annotatR red. Required check names depend on the shared matrix labels, so a rename leaves merges pending.
- Requiring the devel lane makes merges depend on upstream R-devel breakage.
- The deprecation warning uses .frequency 'regularly'; tests must set rlib_warning_verbosity.
- The CI guard fails if node or core Suggests disappear from runners. That is intended, but it can surprise.
- A single aggregated notice is needed because GitHub caps annotations per step and job.
- Importing sf adds its load time to library(annotatR).
- A directory-level waiver would hide all house rules, so it must stay per-file.
- The registry is presence-only; execution is shown by the ledger and CI logs.
- Moving the JS tests leaves stale paths in historical docs.
- Pushing with Version 0.2.0 publishes the development docs as the release site.
- If enabled, the shinytest2 lane in CI may be flaky.
- A hosted Windows runner (administrator, no antivirus) is not a desktop Windows host.
- The DOI may be a reserved draft, and publishing it changes the claim.
- The local --as-cran incoming ERROR must be recorded separately.
- Timings are indicative only.

### Depends on

- T00–T14 complete on main
- The concurrent re-commit of the port landing, with test-export-contract.R restored, .gitattributes committed and the '@CODE@' placeholders resolved
- A version decision before main receives the push (pkgdown mode)
- A first green post-port CI run on a PR before the lint and coverage gates are switched on
- T15 partly ported (the ometiff capability fix may belong to its remainder)
- T18a: results recorded per OS
- T16/T17 only for EX-7 and EX-8
- Repository admin rights for S5

## Synthesised plan (before the HSI-first decision)

Plan to finish the annotatR roadmap. T00–T14 are done, T15 is partly done, and T18a, T16, T17 and T18 have not started, so the roadmap has not been fully run through. Sources: the four reviewed specs, re-checked against the code that has now landed.

**Base.** `main` is at f2682c9 (code commit cb761e5, records commit f2682c9). It is two commits ahead of origin/main 288c1c5 and the working tree is clean. Since the specs were written at 649cf49, only these changed in code: two comments (`R/interop-capabilities.R`:7 and `R/interop-handoff.R`:921 now say 'after 0.2.0'), the V10 canvas focus fix in `atcanvas.js`, `.gitattributes`, and the restored `test-export-contract.R`. Spec line references therefore still hold. House lint is 58, and T18's hard-coded-0.2.1 item is already resolved.

**Structure.**
- Wave 0: maintainer decisions and a baseline PR.
- Wave 1: T15 (Track 2) runs alongside the T18 CI gates (Track 1). Tracks own disjoint files.
- Wave 2: T18a qualifies the native TIFF containment after T15, keeping the roadmap order T15 → T18a → T16.
- Wave 3: T16 starts with a short shared-infrastructure PR, then three parallel sub-tracks with disjoint files: previews and cache, retention, masks and streaming.
- T17-A (harness and regression only) may start once T15 merges and run alongside T16, because it adopts no gate. T17-B calibrates after T16.
- T18-final closes the release.
- Shared files are edited only in one records commit per PR, in merge order (Track 9): NEWS, DESCRIPTION, NAMESPACE/man, README, planning docs, `_pkgdown.yml`, `images-and-backends.Rmd` and `shiny-workflow.Rmd`.

**Conflicts between the specs and how they are resolved.**
1. Closed-image tiles. The plan adopts T15's lookup under the caller's `cache_identity` before `.reopen_image` in `R/backend.R:at_tile`, and drops T16's 'skip `.tile_cache_put` when reopened'.
2. Finding IDs. Both specs proposed A34. A34 is the sf lazy-load import defect; A35 is the planar-separate TIFF silent zeros.
3. The ometiff registry fix (`R/zzz.R:.register_backends`) moves into T15-P1. T15's capability inventory test replaces T18's `test-capability-claims.R`.
4. `tests/qualification/window-resources.R` stays unchanged as archived Linux evidence. It is marked as superseded by T15's full resource lane and T17's P02/P12.
5. Fixtures. One fixture/formula helper (T15's `helper-resources.R`, with a non-aliasing per-dtype formula) serves T16 and T17, instead of three separate ENVI writers.
6. TIFF after T15. TIFFs open windowed after T15, so T16b's eviction fixtures must be PNG or use `annotatR.tiff_engine='eager'`. T16a needs a block-aware lattice operation in the worker; per-row requests would decode the same blocks again for every kept row.
7. Skip classification is done by the owner of each test file, using Track 1's `skip_unverified` helper, which merges first.

**Probes run in this step.** Directory: `<scratch>`
- `tiff::readTIFF(info=TRUE)` reports `planar.config` 'separate' on a planar file and 'contiguous' on a `writeTIFF` file, so the A35 refusal needs no IFD scanner.
- `terra::rast(noflip=TRUE, raw=TRUE)` plus `readValues` reads a planar-separate window exactly, with integer storage. `GTIFF_DIR:2` addresses the 256×256×4 level of `example_multiplex.tif`.
- A processx child started as `Rscript --vanilla --default-packages=NULL` loads only terra and methods, even with `R_DEFAULT_PACKAGES=magick`. It starts and reads a 64×64×4 window in 2.15 s at 221 MiB RSS.
- The sf defect reproduces on an installed f2682c9 build (`lib-f2682c9`): `at_rois()` after `at_load_project()` gives 'no applicable method for st_geometry … list'.
- lintr 3.4.0: a directory exclusion with a per-linter list silences every linter in that directory; per-file entries do not.
- The dependency-only native reproducer still aborts (exit 134). The package's TIFF paths after an ImageMagick TIFF read exit 0: in-process `writeTIFF` (normal and failing path) and the isolated TIFF read. So T18a is a containment qualification, not new isolation work.

**Effort.** About 250 focused hours: T15 70, T18a about 6, T16 about 106, T17 32, T18 40. The roadmap allows 13–23 days for T15–T18. The critical path with three implementers in wave 3 is about 145 h; one implementer needs about 32 focused days. devtools is not installed, so use pkgload, `testthat::test_local`, roxygen2 8.0.0, `R CMD build`/`check` and covr directly. Commit or push only when the maintainer asks.

**annotatr-roadmap folder.** No folder with that name, in any case, exists under <home> (depth 3), <GitHub checkouts> (depth 4), <tmp> or /private/var/folders (depth 4). `git worktree list` shows only the main worktree, and CTTIR/worktrees is empty. Nothing was deleted, because this step is read-only. The improve/roadmap work survives as origin/improve/roadmap 16ddb1d. Paths like /tmp/annotatr-roadmap-legacy in tests are stored strings; the folders are not needed.

### Order

- Standing rule: every PR rebases on the previous merge and ends with one records commit for the shared files (Track 9). NAMESPACE and man/ are only regenerated with roxygen2 8.0.0. No commits or pushes without the maintainer.
- W0-1 [maintainer] Decide the development version (proposed 0.2.0.9000) and the CI gate policy before anything is pushed. All work starts from main f2682c9.
- W0-2 [Track 1 T18-S0 + Track 9] Version records commit on a branch. The maintainer pushes it and opens a PR to get the first post-port CI run. Archive the per-OS testthat output, skip lists, B_tests and the lint notice (expected 58) under planning/evidence/<date>/ci/.
- W1-1 [Track 1 PR-1, merge first] A34: sf import fix, test-installed-reopen.R, delete tests/qualification/installed-windows.R, add the skip_unverified helper and run summary.
- W1-2 [Track 2 T15-P1; developed in parallel with W1-1, merged after it] A35 planar-separate refusal in .tiff_raw_read and in the raster TIFF branch. Fix the ometiff declaration in R/zzz.R and .hsi_backend_caps. Add capability inventory rows.
- W1-3 [Track 1 PR-2] Bring house lint to 0 (test doubles, example, vignette guards, per-file .lintr waivers, at_fix_geometry per decision). Then set lint.yaml blocking: true.
- W1-4 [Track 2 T15-P2] Bounded IFD scan, codec whitelist and parity rules, metadata-only open, budgeted eager fallback, capabilities_fn, protected close_fn, closed-image caching under the caller's identity, strict telemetry keys.
- W1-5 [Track 1 PR-3..5, parallel with W1-4] Node lane under testthat; test-io-project.R fresh process; skip classification in Track 1 files; audit registry; CI capability guard; fixture integrity test; write the release tooling.
- W1-6 [Track 1 PR-6, needs a green CI run of the landed commit] Coverage floor = trunc(min(local clean export, CI B_tests)), with the ratchet comment. Negative-control PR with floor 99 (maintainer pushes).
- W1-7 [Track 2 T15-P3] GDAL/terra processx worker, windowed TIFF reads, worker lifecycle (.onUnload, kill/restart, fork guard), Suggests processx and ps in the records commit.
- W1-8 [Track 2 T15-P4] Independent TIFF writer and pixel matrix, fresh-process resource harness (default and full lanes), TIFF docs and README row, t15 evidence. T15 is then complete.
- W2-1 [Track 3 T18a, after T15] Fresh-process qualification of the failing native-library order through package APIs under both TIFF engines. Record that the upstream dependency abort persists.
- W2-2 [Track 8 T17-A; may start once T15 is merged, runs alongside W2-1 and wave 3, adopts no gate] Performance harness, test-resource-bounds.R, benchmark pointer, self-test and two deterministic quick runs.
- W3-1 [Track 4 T16-0, after T18a] .tile_request factoring, reopen-field digest, tile-cache identity map and drop, preview-cache skeleton, cache purge on close, shared test helpers.
- W3-2 [Tracks 5, 6 and 7 in parallel, after T16-0] T16a: previews, preview cache and non-finite display, including the worker lattice operation for windowed TIFF. T16b: queue, hub and history retention. T16c: at_mask guard, streamed TIFF/NPY export, sidecar-first publication, stream= integration, at_batch_apply handle restoration.
- W3-3 [Track 4 T16-final, after Tracks 5-7 merge] annotatR-options page covering all T15 and T16 options, memory-bounds qualification script, T16 NEWS and _pkgdown.yml.
- W4-1 [Track 8 T17-B, after T16-final] Baseline profile on the agreed reference configuration. Adopt each gate or record it as a known gap with an owner. Rewrite the VALIDATION.md performance section and document the measured envelope.
- W5-1 [Track 1 T18-final] Run release-metadata.R and the release ledger. Reconcile README and other claims (OME, qptiff, whole-slide wording), set release metadata, propose required checks (admin), then run the full verification sequence.

### Tracks

#### Track 1 T18-gates

Work packages:

- T18-S0 baseline PR on f2682c9 after the version decision; the maintainer pushes; archive CI evidence
- A34 sf import fix + tests/testthat/test-installed-reopen.R; delete tests/qualification/installed-windows.R
- skip_unverified helper and aggregated UNVERIFIED summary (merge first)
- House lint baseline to 0, then lint.yaml blocking: true
- Node lane: move tests/audit/*.test.js to tests/testthat/js/ and add test-widget-node.R
- test-io-project.R:67 fresh process; skip classification in owned test files
- Audit registry A01-A35 plus A31/A33 test prefixes
- CI capability guard and fixture-integrity test
- Coverage floor, ratchet rule and negative control
- Release tooling: planning/RELEASE.md, release-gates.csv, release-ledger.R, release-metadata.R
- T18-final: ledger run, claims reconciliation, release metadata, required checks

Owned files: `.github/workflows/lint.yaml`, `.github/workflows/test-coverage.yaml`, `.lintr (new)`, `R/annotatR-package.R`, `R/geometry.R (at_fix_geometry only)`, `R/utils-check.R (only if the quiet transition is approved)`, `inst/examples/reproducible-analysis.R`, `vignettes/reproducible-analysis.Rmd`, `tests/testthat/helper-capabilities.R (new)`, `tests/testthat/setup-capabilities.R (new)`, `tests/testthat/test-installed-reopen.R (new)`, `tests/testthat/test-quiet-transition.R (new, only if approved)`, `tests/testthat/test-widget-node.R (new)`, `tests/testthat/js/widget.test.js and tests/testthat/js/keyboard.test.js (moved from tests/audit/)`, `tests/testthat/test-audit-registry.R and tests/testthat/fixtures/audit-registry.csv (new)`, `tests/testthat/test-ci-capabilities.R (new)`, `tests/testthat/test-fixture-integrity.R (new)`, `tests/testthat/test-io-project.R`, `tests/testthat/test-geometry.R, test-refine-correctness.R`, `tests/testthat/test-app-capabilities.R, test-app-modules-extra.R, test-audit-app.R, test-batch.R, test-control-protocol.R, test-control-http.R, test-export-contract.R, test-persistence-contract.R, test-persistence-source.R, test-training.R`, `tests/testthat/test-widget-canvas.R and test-shiny-modules.R (wave 1 only; handed to Track 5 and Track 7)`, `tests/testthat/test-qupath-native.R, test-provenance-keys.R`, `tests/testthat/test-backend-cuvis-sdk.R, test-backend-tivita.R, test-io-npy.R, test-app-browser.R, test-interop-handoff.R, test-interop-utils.R, test-shiny-app.R, test-reproducible-analysis.R, test-backend-optional.R`, `tests/browser/README.md`, `tests/audit/run-regressions.R, tests/browser/minimal-app.R, tests/qualification/installed-identity.R, installed-persistence.R, qupath-roundtrip.R (only if the nolint-block waiver form is chosen)`, `tests/qualification/installed-windows.R (delete)`, `planning/RELEASE.md (new)`, `tests/qualification/release-gates.csv, release-ledger.R, release-metadata.R (new)`, `CITATION.cff, .zenodo.json, cran-comments.md (T18-final)`

Base: main f2682c9. Branch per PR. Pushing, PRs, negative-control runs and branch protection are maintainer actions. Wave-1 PRs touch only the files listed here. In wave 3 this track only writes release tooling.

PR-1 (merge first):
(a) A34. Add `#' @importFrom sf st_sfc` to R/annotatR-package.R; NAMESPACE is regenerated in the records commit.
- Cause: NAMESPACE imports only rlang and stats, so a fresh library(annotatR) leaves sf unloaded. R/utils.R:.rois_to_tbl then runs do.call(c, ...) over sfc objects and gets a plain list.
- Reproduced on an installed f2682c9 build: at_rois() after at_load_project() fails with 'no applicable method for st_geometry ... list'.
(b) tests/testthat/test-installed-reopen.R uses two audit_fresh() processes (helper-fresh-process.R). Process 2 calls at_rois() FIRST. It asserts:
- the saved ROI ids;
- decoded_bytes == 0;
- NULL handle data and levels;
- literal ENVI and TIVITA windows (c(322,332,323,333), c(122,132,123,133));
- an identical window after at_close_image;
- 'sf' %in% names(getNamespaceImports('annotatR')).
OME rows use skip_unverified. The behavioural check only fails in installed mode (R CMD check, covr). Delete tests/qualification/installed-windows.R.
(c) helper-capabilities.R defines skip_unverified(capability, why = not-installed | fixture-unavailable | not-supported | opt-in | not-applicable, detail). setup-capabilities.R prints the full block and ONE aggregated '::notice title=annotatR unverified capabilities::' line. Every later new test in every track uses this helper.

PR-2 (lint):
- Convert the 17 stop() test doubles to cli::cli_abort(): test-app-capabilities.R:37, test-app-modules-extra.R:146, test-audit-app.R:299/330, test-batch.R:141, test-control-protocol.R:349, test-export-contract.R:18/29/81/86/93, test-persistence-contract.R:63/91, test-persistence-source.R:44, test-shiny-modules.R:156, test-training.R:174, test-widget-canvas.R:98.
- Convert the 5 stop() calls in inst/examples/reproducible-analysis.R.
- Replace the 4 stopifnot() calls in vignettes/reproducible-analysis.Rmd with 3 if (!...) cli::cli_abort() guards.
- Add a root .lintr with exclusions only: 'tests/testthat.R', 'data-raw', and per-FILE list(cttir_condition = Inf) entries for tests/audit/run-regressions.R, tests/browser/minimal-app.R and tests/qualification/installed-identity.R, installed-persistence.R, qupath-roundtrip.R, window-resources.R. Encoding UTF-8, no linters field.
- Never use a directory entry: in lintr 3.4.0 it waives every linter for the whole directory (probe synth/lintr-dir).
- at_fix_geometry, default: `# nolint: cttir_quiet.` with a reason at R/geometry.R:695 and on test-geometry.R:118/229/240 and test-refine-correctness.R:48. Only if the maintainer approves the rename: at_fix_geometry(project, verbose = NULL, call = rlang::caller_env(), quiet = FALSE) with a classed, .frequency='regularly' deprecation warning, plus test-quiet-transition.R.
- Set blocking: true in .github/workflows/lint.yaml once the PR's lint job reports 0.

PR-3 (node lane):
- git mv tests/audit/widget.test.js and keyboard.test.js to tests/testthat/js/. Asset root: process.env.ANNOTATR_INST_DIR || path.join(__dirname,'../../../inst').
- test-widget-node.R: skip_on_cran; withr::local_envvar(ANNOTATR_INST_DIR = system.file(package='annotatR')); system2(node, c('--test', files)) must return status 0; skip_unverified when node is missing.
- Update the comment at test-widget-canvas.R:226 and tests/browser/README.md. The current commands in REGRESSIONS.md change in the records commit.

PR-4:
- Rewrite test-io-project.R:67 with audit_fresh(). fresh_loader() cannot reach the internal .all_roi_ids in installed mode.
- Classify every skip in the files this track owns:
  - the 10 skip_on_os('windows') sites, including test-export-contract.R:39;
  - the inverse skips at test-backend-optional.R:6/13 as not-applicable;
  - remove the vestigial skip at test-audit-app.R:318;
  - symlink tests try file.symlink() first.

PR-5:
- The audit-registry CSV has columns finding, work_package, lane, file, test_pattern, capability, implementing_revision, failing_before_evidence, reviewer_date and covers A01-A35. test-audit-registry.R checks presence only.
- Prefix test names with A33 in test-provenance-keys.R and A31 in test-qupath-native.R.
- test-ci-capabilities.R is active only when GITHUB_ACTIONS=='true' and GITHUB_REPOSITORY=='CTTIR/annotatR'. It requires node plus every DESCRIPTION Suggests package except an explicit optional allow-list (RBioFormats, chromote, shinytest2, covr, ...). Track 2's later additions (processx, ps) are then covered without editing this file.
- test-fixture-integrity.R checks every sha256 manifest with digest on every OS, with a CRLF negative control.

PR-6 (after a green CI run):
- floor = trunc(min(local clean-export covr type='tests', CI B_tests)). Expected 89-90 (local 90.59% at 649cf49, CI 89.03% at 03ce6aa).
- Record the baselines and the ratchet rule (each release: trunc of the minimum of the last three green runs) in test-coverage.yaml.
- Negative control: a draft PR with floor: 99. Record the run id and close it unmerged.

Release tooling (write any time, run at the end):
- release-ledger.R:
  - git-archive export;
  - R CMD build/check;
  - tar listing must not contain planning/, data-raw/, tests/audit|browser|qualification, hsi-workbench, docs/, node_modules, package*.json;
  - ListReporter proof that every registry row ran unskipped;
  - per-file coverage;
  - the CTTIR/.github sha;
  - output outside the repository.
- release-metadata.R checks:
  - DESCRIPTION, NEWS, CITATION and .zenodo agree;
  - the DOI resolves or is absent;
  - planning links resolve;
  - no '@CODE@';
  - no hard-coded future versions;
  - README capability sentences equal at_backend_list().

T18-final:
- Run both scripts.
- README: claim OME only if OME tests executed on at least one CI OS; add the qptiff footnote; align 'whole-slide' wording with the T17 envelope; add the O06 sentence; state supported browsers (Chrome headless shell 156, Playwright 1.64.1).
- Rename the NEWS 0.0.1 heading to 0.1.0.
- Set release version and date per decisions.
- Propose required checks for the admin.
- Record shared CTTIR/.github proposals as dependencies, not edits.

All new code must lint clean. Shared files go through Track 9. Effort: about 32 h for waves 1-3, about 8 h for T18-final.

#### Track 2 T15

Work packages:

- T15-P1: A35 planar-separate refusal (eager and raster TIFF paths) + ometiff declaration fix + capability inventory test
- T15-P2: io-tiff-ifd.R scan/whitelist/parity/block model, metadata-only open, budgeted eager fallback, capabilities_fn, protected close, closed-image caching under the caller's identity, strict telemetry
- T15-P3: io-gdal-worker.R processx worker, windowed TIFF reads, lifecycle, Suggests processx/ps
- T15-P4: independent TIFF writer matrix, fresh-process resource harness (default and full lanes), TIFF docs, evidence

Owned files: `R/backend-tiff.R (handed to Track 5 in wave 3)`, `R/backend-raster.R`, `R/io-tiff-ifd.R (new)`, `R/io-gdal-worker.R (new; handed to Track 5 in wave 3)`, `R/backend.R (handed to Track 4 in wave 3)`, `R/io-window.R (handed to Track 4 in wave 3)`, `R/zzz.R`, `R/interop-capabilities.R`, `R/hsi-meta.R (roxygen only)`, `R/class-image.R (comment only)`, `tests/testthat/helper-tiff-writer.R (new)`, `tests/testthat/helper-resources.R (new; read-only for later tracks)`, `tests/testthat/test-tiff-windows.R (new)`, `tests/testthat/test-window-resources.R (new)`, `tests/testthat/test-windowed-readers.R`, `tests/testthat/test-reader-correctness.R`, `tests/testthat/test-backend-tiff.R`, `tests/testthat/test-tiff-process.R`, `tests/testthat/test-backend-raster.R`, `tests/testthat/test-backend.R`, `tests/testthat/test-interop-capabilities.R`, `tests/qualification/window-resources.R (kept unchanged; listed so no one edits it)`, `planning/evidence/<date>/t15/ (new)`

Follow the reviewed T15 spec, with the changes below. Merge after Track 1 PR-1 so the skip_unverified helper exists. Use it for capability skips, and classify the skips in the test files you own. New code must lint clean: use .at_abort or cli. Use inline `# nolint: cttir_condition.` with a reason only where base conditions must be preserved, as R/io-tiff-process.R does.

P1 (first PR):
(a) A35:
- R/backend-tiff.R:.tiff_raw_read refuses identical(attr(a,'planar.config'),'separate') when samples.per.pixel > 1, with TIFF_UNSUPPORTED.
- R/backend-raster.R:.raster_read's TIFF branch (used when magick is absent) calls .tiff_read_isolated(path, as.is = FALSE, info = TRUE). It applies the same refusal and strips the info attributes before arithmetic.
- Probe synth/a_planar_terra.R shows the attribute is present ('separate' vs 'contiguous').
- Failing-before evidence: 57 of 60 zeros (review15/p1_planar.R).
(b) ometiff declaration:
- R/zzz.R:.register_backends uses .backend_capabilities(TRUE, TRUE, 'raw-scalar-v1', 'native'), which is what .ometiff_read already reports per image.
- R/interop-capabilities.R:.hsi_backend_caps reports ometiff window_read = TRUE, keeps status 'planned'/'unavailable' and an empty qualified_with.
(c) Capability inventory test in test-windowed-readers.R: at_backend_list(), at_image_capabilities() and at_interop_capabilities('hsi') agree with a literal table. This replaces T18's test-capability-claims.R.

P2:
- New R/io-tiff-ifd.R: bounded walker for classic and BigTIFF, II and MM, reading through io-window.R:.window_read_raw; parity rules; codec whitelist; corrected block model; block index.
- .tiff_read becomes metadata-only when the engine is selected. Option annotatR.tiff_engine = 'auto'|'gdal'|'eager'. Check installation with find.package; never call requireNamespace('terra') in the main process.
- .tiff_read_eager scans first, then calls .read_budget(8 x samples over all levels) before spawning the decoder.
- R/backend.R:at_backend_register gets an additive capabilities_fn. capabilities stays a list. at_backend_list, at_image_capabilities and at_read_image evaluate capabilities_fn in tryCatch; a function is never stored in meta.
- R/io-window.R:
  - at_close_image runs close_fn in tryCatch, turns failures into a warning, and always releases the handle;
  - .read_telemetry_add aborts on unknown keys (today NULL + x silently gives numeric(0));
  - delete .memory_snapshot in favour of persistence.R:.holds_pixel_arrays, which has the same body.
- R/backend.R:at_tile, for a handle-less image whose stat-only .source_status() is 'available' and whose descriptor is not .composite_unverified():
  - look the tile up under the CALLER's cache_identity before .reopen_image;
  - on a miss, reopen and read, then store the tile and .read_stats_add under the caller's identity.
  - Today every closed-image call re-reads 149 bytes and caches under a throwaway identity, and at_read_stats(closed)$tiles stays 0 because hsi-meta.R:.read_stats_key uses the reopened identity.
  - This replaces T16's 'skip .tile_cache_put when reopened'.

P3:
- R/io-gdal-worker.R as in the spec:
  - processx worker 'Rscript --vanilla --default-packages=NULL'; JSON-line requests; RDS replies in a 0700 dir announced by id lines;
  - poll_io deadline; kill and lazy restart after a timeout or interrupt; owner-pid fork guard; TMPDIR inside the session tempdir;
  - GDAL_*/GTIFF_*/CPL_*/VSI_* stripped and GTIFF_IGNORE_READ_ERRORS=NO pinned; terra::gdal(warn=3);
  - init self-test (vrt a_nodata=none, INT1S); worker compares GDAL's Block= with the master's model, BACKEND_CONTRACT on mismatch;
  - native-width transfer; self-reported rss/maxrss; graceful quit; test hooks only with ANNOTATR_TEST_HOOKS=1.
- Probe synth/b_worker.R: start plus terra plus a 64x64x4 window takes 2.15 s; only terra and methods are loaded, even with R_DEFAULT_PACKAGES=magick; 221 MiB RSS.
- R/zzz.R:
  - .onUnload calls .gdal_worker_stop();
  - tiff registration uses capabilities_fn and available_fn = .tiff_backend_available;
  - .tiff_available stays as it is for masks.
- .hsi_backend_caps: tiff window_read = engine usable, without loading terra.
- Records commit: DESCRIPTION Suggests processx and ps (>= 1.9.0).
- Apply the Windows decision (default 'eager' on Windows if chosen).
- Coverage: covr does not count code inside the deparsed worker. Cover request validation and contract checks on the master side and keep the handler small, so Track 1's floor holds.

P4:
- helper-tiff-writer.R: an independent writer driven only by the TIFF specification; it must never call package code.
- test-tiff-windows.R: the pixel matrix.
- helper-resources.R:
  - measure_fresh_read with the JIT off, baseline taken before at_read_image, ps self-report;
  - sparse ENVI, SpecCube and TIFF builders;
  - ONE non-aliasing per-dtype value formula (T17's perf_value reduced to each dtype's range). Tracks 4-8 reuse these read-only.
- test-window-resources.R: default lane (skip_on_cran) and full lane (ANNOTATR_RESOURCE_TESTS=true, JSON through ANNOTATR_RESOURCE_EVIDENCE, OME rows through skip_unverified).
- Keep tests/qualification/window-resources.R unchanged (archived Linux evidence) and mark it superseded in IMPLEMENTATION.md.
- Records commit:
  - README TIFF row and the 'decoded whole' sentence;
  - images-and-backends.Rmd: backend table, options, telemetry, close semantics, capabilities_fn migration note;
  - NEWS: A35, engine and option, new Suggests, eager budget preflight, closed-image caching, changed interop capability digest;
  - ADDITIONAL-FINDINGS A35; evidence under planning/evidence/<date>/t15/; status rows.
- Not here: TIFF preview lattice (Track 5); int32/uint32/float64 unless the maintainer decides to accept them. Effort: about 70 h.

#### Track 3 T18a

Work packages:

- Fresh-process regression of the failing native-library order through package APIs, under both TIFF engines
- Archive the dependency-only reproducer result and close T18a in the records

Owned files: `tests/testthat/test-native-tiff-order.R (new)`, `planning/evidence/<date>/t18a/ (new)`, `R/mask-io.R (only if a remaining in-process libtiff warning path is found; wave 2, before Track 7 takes it)`

Start after T15-P4 merges. The roadmap orders T18a after T15 and before T16; the T16 tracks wait for this track.

Current state:
- Every R tiff read already runs in a child process without magick: R/io-tiff-process.R:.tiff_read_isolated, used by .tiff_raw_read, the raster TIFF branch and mask-io.R:.read_mask_matrix.
- The only in-process libtiff use is tiff::writeTIFF in R/mask-io.R:.write_mask_raster.

Probes in this step:
- synth/d_order.R, a copy of planning/evidence/implementation-2026-09-10/native-diagnostic/tiff-handler-order.R with an absolute path, still aborts in 'retained' mode (exit 134, ImageMagick exception-signature assertion). It passes in 'tiff-only' mode.
- synth/c_t18a_child.R: an ImageMagick TIFF read followed by in-process writeTIFF (normal path and failing path) and then at_read_image(example_multiplex.tif, backend='tiff') exits 0 in every mode.

Deliver tests/testthat/test-native-tiff-order.R. In a fresh process (audit_fresh), replay the failing order through package APIs:
1. a magick TIFF read, or at_read_image(<tif>, backend='raster');
2. at_write_mask(format='tiff');
3. at_read_image(example_multiplex.tif, backend='tiff') under annotatR.tiff_engine 'eager' and 'gdal', then at_tile;
4. at_read_mask() of the written TIFF.
Assert the child exits 0 and every value equals its literal. Use skip_unverified when magick or tiff is absent.

Archive both reproducer results under planning/evidence/<date>/t18a/. The records commit sets the IMPLEMENTATION T18a row to 'contained; dependency defect persists'; add NEWS only if behaviour changes. If an in-process R tiff call is shown to raise a libtiff warning after an ImageMagick TIFF read, move that call into the isolated child, mirroring .tiff_read_isolated. Otherwise make no package change. Lint clean, no stop(). Effort: about 6 h.

#### Track 4 T16-infra

Work packages:

- T16-0: .tile_request factoring, reopen-field digest, tile-cache identity map/drop, preview-cache skeleton, close purges caches, shared helpers
- T16-final: annotatR-options page, tests/qualification/memory-bounds.R, T16 records (NEWS, _pkgdown.yml)

Owned files: `R/backend.R (from Track 2; T16-0 only)`, `R/io-window.R (from Track 2; T16-0 only)`, `R/perf.R`, `R/persistence.R (.reopen_image digest in T16-0; then handed to Track 6)`, `R/preview.R (new; cache skeleton in T16-0; then handed to Track 5)`, `R/annotatR-options.R (new; T16-final)`, `tests/testthat/helper-annotatR.R`, `tests/testthat/test-image-caches.R (new)`, `tests/qualification/memory-bounds.R (new; T16-final)`

T16-0 starts after Track 3 merges. It is one short sequential PR that Tracks 5-7 build on.

1. R/backend.R:
- Factor .tile_request() (level, range and band validation, TILE_TOO_LARGE) out of at_tile with unchanged behaviour. Keep T15's caller-identity caching. tests/testthat/_snaps/errors.md (at_tile level message) must stay unchanged.
- In at_read_image, record a digest of the reopen-checked fields: dims, n_bands, level_dims, backend, dtype, band_names, wavelengths, wavelength_unit, pixel_size, pixel_unit, reader_contract.
2. R/persistence.R:.reopen_image records the same digest on success.
3. R/perf.R: add a key-to-identity map and .tile_cache_drop(identity). Do NOT modify the T04-reviewed .centre_range or .cover_shortcircuit.
4. New R/preview.R holding only the preview cache: env, key, get/put/drop/clear/stats. Limits annotatR.preview_cache_bytes (128 MiB, 0 disables) and annotatR.preview_cache_entries (16), per decision.
5. R/io-window.R:at_close_image keeps T15's protected close_fn and drops the old identity's tile and preview entries.
6. tests/testthat/helper-annotatR.R:
- clear_image_caches() also clears the preview cache;
- add register_fake_backend();
- add eager queue fixtures: PNG through the raster backend, or TIFF with options(annotatR.tiff_engine = 'eager'). After T15, windowed TIFF handles hold no arrays and would not exercise eviction.
- Reuse the helper-resources.R builders; add no new ENVI writer.
test-image-caches.R: closing purges both caches; repeated at_tile on a closed image leaves one cache entry under the caller's identity and the second call is a hit (replaces the spec's r6 'no put' regression).

T16-final (after Tracks 5-7 merge):
- R/annotatR-options.R: @name annotatR-options, listing every option with its default and meaning. Include T15's annotatR.tiff_engine, tiff_max_directories, tiff_max_description_bytes, gdal_cache_mb, gdal_worker_start_timeout and tiff_timeout, the T16 options, and the existing cache_size, max_tile_bytes, max_read_bytes, max_npy_header_bytes, control_mask_max_pixels and control_hash_max_bytes.
- tests/qualification/memory-bounds.R: fresh-process ps RSS and gc trajectories for a 100-entry navigation plateau, a 20000^2 sparse ENVI preview, and a 12000x9000 streamed export against at_mask.
- Records commit: NEWS behaviour changes (spec D8); _pkgdown.yml entries for at_write_mask_stream and annotatR-options.
Effort: about 8 h for T16-0 and 8 h for T16-final.

#### Track 5 T16a-previews

Work packages:

- Bounded decimated previews (.preview_plan, .image_lattice, lattice readers for ENVI/TIVITA and the generic fallback)
- Block-aware worker lattice operation for windowed TIFF
- Preview cache use, finite-only stretch, transparent non-finite pixels, optional 8-bit encoding
- Plot reads only the displayed bands

Owned files: `R/preview.R (after T16-0)`, `R/widget-canvas.R`, `R/plot.R`, `R/backend-envi.R`, `R/backend-tivita.R`, `R/backend-tiff.R and R/io-gdal-worker.R (lattice operation only; from Track 2)`, `tests/testthat/test-preview-bounds.R (new)`, `tests/testthat/test-preview-cache.R (new)`, `tests/testthat/test-widget-canvas.R (from wave 3)`, `tests/testthat/test-plot.R`

Start after T16-0. Implement spec D1 and D2, with these corrections.

1. Lattice:
- .preview_plan uses the top-left lattice: s = ceiling(max(d)/max_dim), the same rule as at_mask_preview.
- .image_lattice returns exactly at_tile(img, level)[ys, xs, bands] and never fills the tile cache.
- Dispatch through .lattice_readers only when identical(at_backend_get(name)$tile_fn, <built-in>).
- .envi_read_lattice and .tivita_read_lattice follow the BSQ/BIL/BIP/SpecCube byte formulas.
- The generic per-row fallback is only for third-party backends and windowed OME.
2. Windowed TIFF (handle$windowed after T15) must not use the per-row fallback, which would decode every block once per kept row. Add a worker operation that reads block-aligned, full-width row groups within annotatR.preview_chunk_bytes and returns only the [ys, xs, bands] samples, subsampled inside the worker, so each block is decoded once. Byte oracle: the writer-reported bytecounts of the intersecting blocks. Eager TIFF arrays index handle$levels.
3. Display:
- .view_display_array accumulates band means in one pass;
- .display_stretch replaces .stretch01: quantiles over finite samples only; non-finite samples become NA and get alpha 0 in RGBA;
- .encode_display_png uses depth 8 if the maintainer adopts it.
4. R/plot.R:.image_display_df resolves the displayed bands first and reads only those through the lattice. Today it reads every band of the display level, so a 20000^2x3 image fails with TILE_TOO_LARGE and a 4096^2x16 cube with READ_BUDGET_EXCEEDED.
5. Preview cache:
- look up in .image_data_uri_result after the magick availability check;
- never cache failures;
- serve a hit only if the image holds arrays, has no descriptor, or .source_status is 'available';
- the 'decoder exploded' test in test-widget-canvas.R sets annotatR.preview_cache_bytes = 0.
- Do not reintroduce 'skip .tile_cache_put when reopened'.

Tests: test-preview-bounds.R and test-preview-cache.R as specified. test-plot.R: identical() to a test-local copy of the old algorithm. Classify the skips in test-widget-canvas.R and test-plot.R.

Records commit: images-and-backends.Rmd 'Memory discipline' (lattice bounds, preview cache, replace 'Closing does not purge the shared tile cache'); NEWS.
Effort: about 30 h.

#### Track 6 T16b-retention

Work packages:

- R/retention.R: releasable check with reopen digest, release without close_fn, MRU budgets, memory report
- App and recovery-queue retention, history pruning, non-materialising checkpoint reload
- Hub retention
- Reopen once per call in extraction and per entry in training

Owned files: `R/retention.R (new)`, `R/app-state.R`, `R/app-builder.R`, `R/control-state.R`, `R/control-commands.R`, `R/app-control-sync.R`, `R/extract.R`, `R/training.R`, `R/persistence.R (.save_checkpoint only, after T16-0)`, `tests/testthat/helper-queue.R (new)`, `tests/testthat/test-queue-retention.R (new)`

Start after T16-0. Implement spec D3.

R/retention.R:
- .handle_releasable requires pixel arrays, .strip_persisted_handle, .source_status 'available' and a matching reopen-field digest. This pins images whose metadata was edited after reading, such as at_example_image('multiplex'), whose band_names are overwritten.
- .release_snapshot never calls close_fn, because store, hub and tab copies may share the handle. It mints a new cache_identity, clears read_generation and drops the old identity's tile and preview entries.
- .queue_release_handles walks in MRU order within count and object.size budgets.
- Add .queue_memory_report and option accessors.

R/app-state.R:
- update rv$mru in .state_adopt;
- call .state_retain at the end of .state_load, .state_replace (also covering rv$recovery_queue), .state_restore_queue (reopen before adopting) and .state_save;
- prune rv$history to annotatR.app_history_entries; history_limit comes from annotatR.app_history_depth.

Hub: hub$mru and .hub_retain in R/control-state.R:.hub_project, R/control-commands.R:.cmd_goto and R/app-control-sync.R:.hub_push_from_app.

R/persistence.R:.save_checkpoint reloads NULL entries without materialising pixels. Today it calls at_load_project, which uses .restore_project(materialize = TRUE).

R/extract.R: at_extract, at_extract_spectrum and at_extract_pixels reopen once per call. R/training.R reopens once per entry, and only when include_images is TRUE.

R/app-builder.R: add retained_images to exportTestValues and document rv$mru.

Fixtures must be eager: PNG, or annotatR.tiff_engine = 'eager'. Put queue helpers in the new helper-queue.R.

The at_batch_apply handle restoration lives in Track 7 (R/batch.R); agree its test with Track 7.

Records commit: shiny-workflow.Rmd (retention and history bounds, revisit cost, IMAGE_CHANGED after eviction); NEWS.
Effort: about 26 h.

#### Track 7 T16c-masks

Work packages:

- at_mask size guard (MASK_TOO_LARGE) and mask plan
- Windowed exact rendering and lattice mask previews
- Exported at_write_mask_stream with pure-R TIFF/BigTIFF and NPY sinks plus cancellation
- Sidecar-first staged publication; stream= in exports; at_batch_apply handle restoration; app overlay/summary integration

Owned files: `R/mask.R`, `R/mask-metadata.R`, `R/mask-stream.R (new)`, `R/mask-io.R (from wave 3)`, `R/io-npy.R`, `R/export-policy.R`, `R/batch.R`, `R/interop-handoff.R`, `R/app-modules.R`, `tests/testthat/test-mask-guard.R (new)`, `tests/testthat/test-mask-stream.R (new)`, `tests/testthat/test-mask-stream-cancel.R (new)`, `tests/testthat/test-shiny-modules.R (from wave 3, only if overlay or summary expectations change)`, `tests/qualification/npy-stream-check.py (new)`, `vignettes/masks.Rmd`

Start after T16-0. Implement spec D4 to D7.

R/mask.R:
- .mask_max_pixels guard after .resolve_mask_dims and before any matrix(); default per decision.
- at_mask_stack checks pixels x layers.
- MASK_TOO_LARGE with details: width, height, pixels, limit_pixels.
- Add .mask_plan, .legend_skeleton, .apply_overlap (factored from .rasterize_per_roi), .mask_render_window (uses the existing .cover origin path), a new .cover_lattice and .mask_preview_lattice.
- The reviewed .centre_range, .cover_polygon and .cover_shortcircuit stay untouched.
- The at_mask(42) snapshot in _snaps/errors.md must stay unchanged.

R/mask-metadata.R: split structural checks from pixel checks.

New R/mask-stream.R:
- exported at_write_mask_stream;
- pure-R .tiff_stream_sink: strips, little-endian, BigTIFF switch, header committed last through 'r+b';
- .npy_stream_sink: C order, header last;
- progress cancellation raises at_cancelled_error EXPORT_CANCELLED.

R/mask-io.R: .mask_legend_payload; at_write_masks gets stream=.
R/io-npy.R: .npy_header_bytes shared by both writers.
R/export-policy.R:
- .export_bundle publishes sidecars first, names stages '.export-stage-*.partial', and restores backups through an on.exit completion flag;
- .export_outcome re-signals cancellation and interrupts;
- .export_project_file gets stream=.
R/batch.R:
- stream= in at_export_all and .export_session_items through .write_project_mask;
- at_batch_apply restores the input handle state, releasing only handles it materialised itself.
R/interop-handoff.R: pass the guard error through to the control 'export' response; no streaming.
R/app-modules.R:
- overlay and Summary use .mask_preview_lattice and show the MASK_TOO_LARGE reason;
- stats use the bounded count pass for exact plans;
- 'Export this mask' goes through .write_project_mask.

Never write masks with terra or GDAL: terra's INT2U output declares NoData 65535, which reads back as NA (probe t16rev/r3).

Tests: test-mask-guard.R, test-mask-stream.R, test-mask-stream-cancel.R. The callr hard-kill test waits with poll_io, never a sleep loop. Decode streamed TIFFs with the isolated libtiff reader (.tiff_raw_read) and with GDAL. npy-stream-check.py uses only the standard library; run it with python3 -I.

Records commit: masks.Rmd 'Large masks' section (owned here); NAMESPACE export via roxygen; NEWS (guard, sidecar-first publication, stream='auto', at_batch_apply).
Effort: about 34 h.

#### Track 8 T17

Work packages:

- T17-A: fresh-process installed-build harness in tests/qualification/performance/ (scenarios P00-P14, fixtures, gates, self-test)
- T17-A: tests/testthat/test-resource-bounds.R metamorphic window-scaling regression; data-raw/benchmark.R pointer
- T17-B: baseline on the reference configuration, gate adoption or known gaps with owners, VALIDATION.md calibration, measured envelope docs

Owned files: `tests/qualification/performance/ (new: run.R, worker.R, measure.R, fixtures.R, scenarios.R, summarize.R, environment.R, macos_rusage.py, README.md)`, `tests/testthat/test-resource-bounds.R (new)`, `data-raw/benchmark.R`, `planning/evidence/<date>/performance/ (new; T17-B)`

T17-A starts after T15 merges and adopts no gate, so it can run alongside T18a and T16. T17-B starts only after T16-final.

Build the harness as in the reviewed spec:
- an installed tarball built from a git ls-files snapshot, never rsync and never load_all for evidence;
- one fresh processx worker per job, with a ps sampler;
- per-OS memory sources, validity flags (page-ins, swap-ins) and the status taxonomy;
- deterministic v1 fixtures verified independently with GDAL (stars RasterIO; raw VRT for SpecCube);
- summarize.R gates.

Adjustments in this plan:
1. Reuse the T15 helper-resources.R builders and formula wherever possible.
2. Run TIFF scenarios under both annotatR.tiff_engine values. The eager k-factor envelope needs 'eager'.
3. Report gaps that T16 closes (P04, P06, P10) as known_gap(T16) until T17-B; there they become pass or known_gap_now_passing.
4. Evidence mode refuses a tree that changes during the run and untracked R/ or inst/ files.
5. New driver code must lint clean under the blocking house rules: cli::cli_abort, never stop() or stopifnot().
6. Report mismatches between registry and per-image capabilities as findings.

tests/testthat/test-resource-bounds.R:
- mandatory lane, skip_on_cran;
- one audit_fresh process per case: ENVI BSQ, ENVI BIP, TIVITA SpecCube;
- 512x384 vs 16384x6144 with a formula patch over the window and two in-extent warm-ups;
- exact bytes and calls; heap difference <= 64 KiB; Rprofmem alloc_max identical and <= window doubles + 64 KiB.
- If seek-for-write fails on NTFS, fall back on Windows to 8192x3072 with an explicit skip_unverified reason.
data-raw/benchmark.R becomes a pointer to the quick profile.

T17-B:
- Run the baseline profile only on the agreed reference configuration. This Mac is refused by the preflight: 10.6 of 12 GiB swap in use, 4.2 GiB available.
- The records commit:
  - rewrites the VALIDATION.md performance section with gate type, baseline and status for every row;
  - adds the measured envelope to images-and-backends.Rmd and qualifies shiny-workflow.Rmd's 'nothing is read until you visit it';
  - replaces README's 'must fit in memory';
  - adds ANALYSIS O07 (checkpoint generation files) and O08 (full-source hashing) with owners per decision;
  - updates REGRESSIONS' benchmark inventory.
- Archive the evidence.
Effort: about 22 h for T17-A and 10 h for T17-B.

#### Track 9 Integration

Work packages:

- Per-merge records commit applied in merge order
- Finding-ID allocation (A34 sf import, A35 planar-separate TIFF)
- Version and Suggests edits per decision

Owned files: `NEWS.md`, `DESCRIPTION`, `NAMESPACE and man/*.Rd (roxygen2 8.0.0 output only)`, `_pkgdown.yml`, `README.Rmd and README.md (T15-P4 TIFF row, then T17-B envelope wording, then T18-final claims)`, `vignettes/images-and-backends.Rmd (T15-P4, then T16a, then T17-B)`, `vignettes/shiny-workflow.Rmd (T16b, then T17-B)`, `planning/IMPLEMENTATION.md, ROADMAP.md, ANALYSIS.md, REGRESSIONS.md, ADDITIONAL-FINDINGS.md, VALIDATION.md`, `planning/evidence/<date>/ci/ (new)`

This track owns the shared files and does no feature work. Merge order is the order list. Each implementing PR ends with exactly one records commit, made after rebasing on the previous merge, that edits only these files. The track's author writes the content.

Rules:
- NEWS: entries under '# annotatR (development version)'.
- DESCRIPTION: Version in W0 per the decision; Suggests processx and ps (>= 1.9.0) in T15-P3; nothing else without a decision.
- NAMESPACE and man/: regenerate with roxygen2 8.0.0 (Config/roxygen2/version); never hand-edit.
- README.Rmd: re-knit to README.md in the same commit.
- Shared vignettes are edited only in the waves named above.
- Planning records:
  - IMPLEMENTATION rows for T15, T18a, T16, T17 and T18;
  - the ROADMAP status sentence;
  - REGRESSIONS node paths and benchmark inventory;
  - ANALYSIS O07/O08 (T17-B);
  - VALIDATION performance section (T17-B);
  - ADDITIONAL-FINDINGS: A34 = sf lazy-load import defect (Track 1 PR-1) and A35 = planar-separate TIFF silent zeros (T15-P1). Both specs had proposed A34.
- Keep historical logs and evidence unchanged; new evidence goes under planning/evidence/<date>/.
- Records-only commits need only link, mapping and syntax checks (VALIDATION rule).
Effort: about 6 h spread over the merges.

### Decisions needed

- Development version before main is pushed (blocks W0-2). Proposed: 0.2.0.9000 now, which keeps the pkgdown development site under /dev; with Version 0.2.0, a push deploys development docs to the release site root. Also decide the release number (0.2.1 vs 0.3.0), given the breaking changes listed below.
- Scope and schedule. The reviewed specs total about 250 focused hours (T15 70, T18a about 6, T16 about 106, T17 32, T18 40), against the roadmap's 13-23 days for T15-T18; T16 alone is about 13 days vs 3-5 planned. Approve, or cut: for example, NPY-only streaming with the pure-R TIFF/BigTIFF writer deferred, or T17 without its release profile. Optional compression: start T16c (it touches no T15 files) during T15. That deviates from the roadmap order T15 -> T18a -> T16 and must be recorded.
- TIFF execution model (T15). Proposed: the isolated processx terra/GDAL worker under annotatR.tiff_engine='auto', which costs about 200-220 MiB extra RSS per session and a 2.2 s first start. Alternative: in-process terra (about 9.6 ms per window), to be revisited only after T18a.
- New Suggests processx and ps (>= 1.9.0). Both are already installed with callr. Without terra and processx, TIFF falls back to the eager reader.
- TIFF sample types int32, uint32 and float64. Proposed: keep refusing them, as tests and vignette promise today. GDAL decodes the reference fixtures exactly, but accepting them would make readability depend on the installation.
- JPEG-compressed RGB TIFF. Keep accepting it, as today, with decoder-defined values flagged as lossy, or refuse it under raw-scalar-v1. The codec whitelist refuses ZSTD, LZMA, WEBP, LERC, JPEG-XL, JPEG 2000, predictor 3 and bytecount-0 blocks either way.
- Windows. Proposed: default annotatR.tiff_engine='eager' on Windows until T18 qualifies the worker. Alternative: enable the worker there and treat windows-latest failures as T18 blockers.
- Accept these user-visible breaking changes for the next version:
- the eager TIFF budget preflight (huge TIFFs need annotatR.max_read_bytes raised);
- planar-separate TIFFs refused by the eager reader (correct under the engine);
- an at_mask guard with default annotatR.max_mask_pixels = 2^27, which refuses masks it produces today, such as 12000x12000;
- closing an image purges its caches;
- sidecar-first publication with '.partial' stage names;
- transparent non-finite canvas pixels;
- a changed interop capability digest, which is recorded in training and handoff manifests.
- T16 option defaults. Proposed:
- annotatR.app_retained_images 3 and app_retained_bytes 512 MiB;
- app_history_entries 10;
- preview cache 128 MiB / 16 entries;
- canvas_max_dim 2048;
- mask_block_bytes 8 MiB;
- stream='auto' as the default for at_write_masks and at_export_all (output bytes are unchanged below the limit).
- Canvas PNG at bit depth 8. Proposed: yes; it halves stretched-preview data URIs and changes values by at most 1/255. Alternative: byte-identical 16-bit encodes.
- touches=TRUE and line ROIs above the mask limit. Proposed: refuse with STREAMING_UNSUPPORTED. Alternative: an exact all-touched rule, which would change at_mask semantics.
- at_fix_geometry verbose -> quiet, a public API change that the 2026-10-18 audit left as a release decision. Proposed: an inline cttir_quiet waiver now, which is non-breaking. Or approve the deprecation path at_fix_geometry(project, verbose = NULL, call = rlang::caller_env(), quiet = FALSE) and choose a removal version.
- CI policy (the audit called it 'a decision for the shared CTTIR workflows').
- Lint becomes blocking at house count 0 with per-file cttir_condition waivers. Alternatives: nolint blocks, or converting the 27 driver calls.
- Coverage floor trunc(min(local, CI)), about 89-90, with a per-release ratchet.
- Required checks: R-CMD-check macOS, windows and ubuntu (release), ubuntu oldrel-1, lint, test-coverage. Devel, oldrel-3 and pkgdown stay informational.
- Enable the shinytest2 lane on GitHub Linux, or not.
- Keep the shared workflows at @main, or pin them by sha, which contradicts the 'move together' comment.
- Maintainer and admin actions that no agent may take:
- push branches and open PRs: the baseline PR and the negative controls (lint injection, floor 99, sf-import revert);
- turn on branch protection with PR-only merges and no bypass;
- route the shared CTTIR/.github proposals: success artifacts, node/Playwright lane inputs, oldrel-3 Bioconductor handling, per-file coverage.
- T17 reference hardware and configuration for latency gates. This M1 is under memory pressure. The ROADMAP default applies until then: a synthetic baseline and no large-data speed claims.
- Owners:
(a) Checkpoint generation files are never deleted, and every save and every autosaved edit writes one file per non-NULL queue entry (R/persistence.R:.save_checkpoint). Choose a retention policy and an owner.
(b) Full-source SHA-256 cost in at_interop_manifest(hash_sources = TRUE), at_export_qupflowr, at_training_export and the control hub's .hub_state for the current entry.
- R minimum. 'Depends: R (>= 4.1.0)' is unverified: only 4.6.1 is available locally, CI covers newer R, and oldrel-3 fails on Bioconductor 3.18. Raise it to the tested floor or add an old-R lane.
- CRAN. R CMD check --as-cran fails its incoming check on the name conflict with Bioconductor 'annotatr'. Rename the package, skip CRAN, or accept the error.
- DOI 10.5281/zenodo.21889921 in CITATION.cff returns 404, and .zenodo.json says the record is not yet published. Publish the record or remove the DOI.

### Blocked on the original machine

- OME-TIFF via RBioFormats: no Java runtime (/usr/libexec/java_home finds none), and RBioFormats and rJava are not installed. This blocks:
- T15's OME resource lane and the investigation of size-dependent OME memory (archived Linux evidence: open +220.6 vs +270.6 MiB, window +1.6 vs +30.9 MiB);
- T17's P12/G-OME;
- T18's OME evidence.
The code can still be written. CI runners that load RBioFormats (macOS, Windows, Ubuntu release/devel/oldrel-1) can run it.
- Windows host. Unverified here:
- T15's worker pipes, kill and TMPDIR hygiene;
- non-sparse large fixtures on NTFS (T15, T16, T17);
- T16's 'r+b' header patch and staged unlinks;
- T18's Windows-host persistence.
Only the hosted windows-latest CI runner is reachable, and it is not a desktop host.
- Linux-only measurements need a Linux runner: /proc VmHWM after clear_refs, rchar and read_bytes, the dd iflag=nocache cache drop, and a rerun of the archived tests/qualification/window-resources.R.
- Timing baselines: this Mac has 10.6 of 12 GiB swap in use and 4.2 GiB available, so the T17 baseline preflight refuses to run. Latency gates need a quiet reference machine. Structural gates and quick profiles can still run here.
- External data and SDKs: the CUVIS SDK (CUVIS stays eager), private TIVITA data, and permitted real large fixtures (vendor WSI/qptiff, Cubert).
- QuPath 0.7.0 consumer round trip (tests/qualification/qupath-roundtrip.R): QuPath is not installed and there is no Java.
- Python numpy, tifffile and PIL are not installed (python3 3.9.6). window-resource-fixtures.py, mask-raster-exports.py and fixture regeneration cannot run. The stdlib-only npy-stream-check.py can.
- PDF manual: there is no LaTeX, qpdf or ghostscript, so R CMD check runs with --no-manual here.
- Only R 4.6.1 and GDAL 3.13.3 are available locally. The R (>= 4.1.0) claim and the GDAL < 3.7 engine-unavailable path can only be checked on CI or another host (for example Ubuntu 22.04); here the latter can only be mocked.
- Steps that need a maintainer push or admin rights: the first post-port CI run, the coverage floor value, the negative-control runs and branch protection. cb761e5 and f2682c9 are not on origin yet.
- No secret scanner is installed (gitleaks, trufflehog), so the O06 history scan cannot run.
- Legacy fixture regeneration: tests/fixtures/legacy-f69bf20/generate.R needs /tmp/annotatr-roadmap-baseline-source, which no longer exists. The pinned bytes are still checked by test-persistence-legacy.R.

### Verification sequence

- 1. Tree and documentation sync. git status shows only intended changes. `Rscript -e 'roxygen2::roxygenise()'` leaves NAMESPACE and man/ unchanged (roxygen2 8.0.0). README.Rmd re-knits to an identical README.md. release-metadata.R finds no '@CODE@' and no hard-coded future versions, and every planning link resolves.
- 2. Full suite on a clean export (`git archive HEAD | tar -x -C $X`): `NOT_CRAN=true Rscript -e 'testthat::test_local("$X", stop_on_failure = TRUE)'`.
- Expect 0 failures, errors and warnings.
- Every skip appears as 'UNVERIFIED <capability> (<why>)' in the aggregated summary.
- Compare totals with the 827-test baseline in planning/evidence/2026-10-18/tests-full.log.
- devtools is not installed; use pkgload and testthat directly.
- 3. Engine and lifecycle lanes. Rerun test-tiff-windows.R, test-reader-correctness.R and test-backend-tiff.R with ANNOTATR_TEST_HOOKS=1, under annotatR.tiff_engine 'gdal' and 'eager'. Run test-native-tiff-order.R in a fresh process. Afterwards, no Rtmp* or annotatr-* directories remain in tempdir() and no worker pid survives .gdal_worker_stop(). Rerun the copied dependency reproducer: 'tiff-only' exits 0 and 'retained' exits 134, which shows containment rather than an upstream fix.
- 4. Resource lanes on an installed build (`R CMD INSTALL --library=<scratch lib>` of the export).
- The default lanes run in step 2: test-window-resources.R, test-resource-bounds.R, the byte tests in test-preview-bounds.R, and the bounded-memory test for streamed masks.
- Full lane: `NOT_CRAN=true ANNOTATR_RESOURCE_TESTS=true ANNOTATR_RESOURCE_EVIDENCE=<dir> Rscript -e 'testthat::test_file("tests/testthat/test-window-resources.R")'`.
- Run `Rscript tests/qualification/memory-bounds.R`.
- Run `python3 -I tests/qualification/npy-stream-check.py <streamed.npy>`.
- Run tests/qualification/installed-identity.R and installed-persistence.R against the installed build.
- 5. Node: `node --test tests/testthat/js/widget.test.js tests/testthat/js/keyboard.test.js` passes all tests (49 at f2682c9). test-widget-node.R runs the same tests through testthat against the installed assets.
- 6. Browser lanes. Repeat after T15 and after T16, as VALIDATION requires browser journeys to be repeated after backend changes.
- shinytest2: `NOT_CRAN=true ANNOTATR_BROWSER_TESTS=true CHROMOTE_CHROME=$HOME/Library/Caches/org.R-project.R/R/chromote/chrome/156.0.8078.12/chrome-headless-shell-mac-arm64/chrome-headless-shell Rscript -e 'testthat::test_local(filter = "app-browser|widget-canvas")'`.
- Playwright: start `Rscript tests/browser/widget-app.R` or `Rscript tests/browser/app-journey.R` in the background. Run `node tests/browser/widget.cjs`, `app-journey.cjs` and `action-origin.cjs` with PLAYWRIGHT_MODULE=<scratch> and CHROMIUM_PATH set to the headless shell. Each must exit 0 with no page errors. minimal.cjs needs a scratch library without magick.
- 7. Build and check.
- `R CMD build --no-manual $X`.
- `_R_CHECK_FORCE_SUGGESTS_=false R CMD check --as-cran --no-manual annotatR_<ver>.tar.gz`: Status shows only the known CRAN-incoming name-conflict ERROR (a maintainer decision), 0 WARNINGs, and every NOTE reviewed.
- Plain `R CMD check --no-manual`: Status OK.
- `tar tzf` contains none of planning/, data-raw/, tests/audit, tests/browser, tests/qualification, hsi-workbench, docs/, node_modules or package*.json.
- 8. Lint. CTTIR house linters (config/lint-cttir.R from CTTIR/.github main) with the repository .lintr report 0 findings (58 at f2682c9). Three negative controls must each be reported, then reverted: `verbose = FALSE` in a testthat file, `function(verbose = TRUE)` in tests/browser/*.R, and stop() in a new tests/qualification file.
- 9. Coverage: `Rscript -e 'cv <- covr::package_coverage("$X", type = "tests"); print(covr::percent_coverage(cv))'` must be at or above the floor. Write a per-file report for the audited and new files (export-policy.R, backend-tiff.R, io-tiff-ifd.R, io-gdal-worker.R, mask-stream.R, retention.R, preview.R) and compare with CI B_tests.
- 10. Benchmarks.
- `Rscript tests/qualification/performance/run.R --self-test`.
- Two `--profile quick` runs; perf_compare_deterministic finds them identical.
- `--profile baseline` on the reference configuration. The structural gates must pass or be recorded as known_gap(owner): G-WIN-BYTES, G-WIN-HEAP, G-WIN-RSS, G-OPEN-META, G-WARM-HIT, G-STALE, G-PREVIEW-DIMS, G-NAV-BOUND, G-SAVE-STRUCT, G-RESUME, G-EXTRACT, G-EXPORT, G-CACHE, G-DETERMINISM.
- Latency is reported only on size S with at least 20 unflagged samples.
- Archive summary.md and results under planning/evidence/<date>/performance/.
- 11. Metadata and site. `Rscript tests/qualification/release-metadata.R` passes. pkgdown: install themakR from the sibling checkout ../themakR into a scratch library, then build the site from the export with a development mode that matches the version; otherwise use the CI pkgdown run.
- 12. CI and ledger (needs a maintainer push).
- The PR is green on every required check.
- The negative-control PRs (lint injection, floor 99, sf-import revert) fail, with run ids recorded.
- The per-OS UNVERIFIED summaries are reviewed.
- OME tests were executed, not skipped, on at least one CI OS before any OME claim.
- windows-latest ran the audit_fresh persistence tests and test-installed-reopen.R.
- Finally, `Rscript tests/qualification/release-ledger.R --out <dir outside the repo>` maps every README and NEWS claim to a verified item; any claim without one is reworded or marked unverified.
