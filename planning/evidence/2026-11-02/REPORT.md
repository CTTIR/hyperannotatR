# hyperannotatR 0.3.1 public maintenance handover

Status: locally validated. The candidate is local and unsubmitted. Hosted CI and real
production use have not been verified for these commits.

## Outcome

The package keeps its HSI-first annotation purpose and existing public APIs.
Repairs protect quantitative input provenance, resumable annotations and partner
commits. TIVITA profile changes and ENVI discovery changes can no longer silently
substitute differently interpreted pixels. Closed-reader cache/accounting stays
consistent. Invalid band indices and calibration references fail explicitly.

Partner commits retain memory-only pixels, stage project/receipt writes together,
and reject stale or redirected replay. Failed control startup releases only its
own resources. Instance-scoped commit keys do not collide. App and control input
paths validate known image/import companions before opening them, including
staged imports and session loading. Rejected requests preserve current work.

Full masks now check dimensions and a conservative working-array estimate before
allocation. Core examples and export tests run without optional PNG/TIFF readers.
Citation metadata no longer claims an unregistered DOI/date; documentation explains
actual calibration assumptions, source relinking, recovery and resource limits.
The shared CI coverage caller now requires 85%, with no new workflow steps.

Findings A37–A51 are registered in `planning/ADDITIONAL-FINDINGS.md`. Focused
regressions failed against the preserved baseline before repairs. Independent
review and direct browser/HTTP workflows challenged the combined changes.

## Verification

Host: R 4.6.1, macOS 27.0.1 arm64. Bio-Formats checks use rJava 1.0-18,
RBioFormats 1.12.0, Bio-Formats 7.3.0 and Java 17.0.21. Documentation uses
roxygen2 8.0.0 and pkgdown 2.2.1. These are observed versions, not a claim that
all declared supported environments were tested.

| Check | Observed result |
| --- | --- |
| Full installed test instrumentation | 5,504 passed, no failures/warnings, 8 named skips; runtime/test inputs unchanged |
| Test coverage | 91.87301% (11,836/12,883 lines), above 85% floor |
| Full as-CRAN, manual/incoming checks enabled | 0 errors, 0 warnings, 1 new-submission NOTE; 5,462 passed, 13 named skips |
| Minimal-dependency as-CRAN | 0 errors, 0 warnings, 1 new-submission NOTE; 3,420 passed, 108 expected optional/CRAN skips |
| JavaScript canvas/keyboard | 59/59 tests passed |
| Installed first use | Exact ROI sums from a 40-band cube; 100-pixel mask; TIFF/GeoJSON/QuPath output; save/reload; closed-reader reuse; invalid band rejection passed |
| Fresh-process qualification | Raster/spectral/relinked pixels, extraction, rendering, stable IDs, RNG and continued editing passed |
| Real browser | Drawing, protected ROIs, undo/redo, stale events, calibration assumptions/overrides, failed-input recovery, save/resume and verified ZIP export passed |
| Installed spectral app | 128×128×40 ENVI; natural RGB to band-12 grayscale; point save and independent-browser resume preserve exact ROI and entry identity |
| Real control HTTP | Five external companion input cases rejected without state changes; valid inputs recover |
| Documentation site | 186 HTML pages; 9,721 local references; no broken targets; desktop/mobile/dark navigation and branding passed |
| Readable manual | 139 pages visually reviewed; 155 TOC entries and 1,875 numeric internal links agree; zero clipping/glyph/font defects |
| Metadata/workflows | CFF schema and synchronized draft version passed; actionlint passed |
| House lint | 84 report-only findings, versus 81 baseline; three additions are deliberate allocation-sentinel errors in regression tests |

The final source archive is `hyperannotatR_0.3.1.tar.gz`, 5,100,961 bytes,
SHA-256 `885217e497a2df441f096be466e88c6d3011aef0920bc35c5b84162b2f1fe668`.
All 549 package input files present in the working tree match the archive; the
build-added DESCRIPTION metadata is expected. The 575-file package excludes
planning/workbench trees, `tests/browser`, `tests/qualification` and
machine-specific home paths.
A limited credential-pattern scan found no matches; it is not a universal secret
or dependency-vulnerability audit. GitHub reported no Dependabot alerts.

All 1,016 originally inventoried public files, the original branch/status and
594 protected fixture/schema/asset/historical-evidence files remain unchanged.
The excluded live annotation workspace and private datasets were not accessed.

## First use on this machine

The audit has installed the exact archive into its `final-library-3` directory.
From the external evidence directory, run:

```sh
./run.sh Rscript first-use.R final-library-3 another-first-use
./open-app.sh
```

Use a new output directory for the first command. The app launcher uses bundled
ENVI data, writes to `try-app`, and resumes its checkpoint on subsequent starts.
It accepts an explicit demo output directory as its first argument. Inspect the
Cube panel before interpreting values: the bundled cube declares wavelengths
450–900 nm, unknown value units and missing physical calibration. A view setting
such as band 12 is temporary and resets to natural RGB on a new app instance.

For another environment, install R and the DESCRIPTION dependencies first.
Spatial source installs need GDAL, GEOS, PROJ and udunits; PNG examples need
magick/ImageMagick, TIFF output needs tiff, and the app needs the suggested Shiny
packages listed in README. Java/Bio-Formats and the vendor SDK are optional for
their respective readers. Install the archive and follow the executed README:

```sh
R CMD INSTALL hyperannotatR_0.3.1.tar.gz
Rscript -e 'library(hyperannotatR); print(at_dims(at_example_image("cube")))'
```

## Limits and next release action

Local package, core workflow, failure-path, scientific-fixture, installation and
documentation criteria are satisfied on the observed local environment. These results do not establish physical
calibration or annotation quality on a study dataset. Assumed reference lengths
stay provisional and never silently change pixel geometry or image calibration.

Explicitly deferred work:

- Windows/Linux and minimum-R qualification, hosted CI, the real CUVIS SDK and
  real partner clients. Public/synthetic fixtures do not certify vendor data or
  a deployed multi-user service.
- Streaming/eager TIFF redesign, within-ROI extraction streaming, aggregate
  mask-stack memory limits and cache/retention policy. Array budgets exclude RSS,
  native/geometry buffers and other simultaneously retained arrays.
- Crash-atomic multi-file commits and concurrent writers. Handled failures roll
  back or retain reported recovery backups; writers to one destination must be
  serialized. Size/mtime source checks do not prove content identity.
- OS-level sandboxing for custom readers, external reader references and
  concurrent filesystem replacement. App/control path checks have that scope.
- Existing report-only house-lint debt, toolchain PDF layout behavior and
  low-contrast ANSI temporary-path output in dark-theme site examples.

The standard R-generated manual retains nine pre-existing clipped words. The
separate `manual-review/candidate3/hyperannotatR-manual.pdf` is a readable copy
from the exact checked source, with only TeX line-breaking adjustments. Its
139 pages, text, navigation and embedded fonts were verified; the original check
PDF remains archived. Pandoc's deprecated math-rendering flags are toolchain
messages, not hidden package-check warnings.

Next: review the local maintenance commits, authorize publication to main, and
observe the required hosted platform checks. Only then prepare a versioned
release or CRAN/Zenodo submission with actual publication metadata and any
required external qualifications. No push, release, submission or deployment
occurred during this audit.
