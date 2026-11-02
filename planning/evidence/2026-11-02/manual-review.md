# hyperannotatR 0.3.1 manual review

The completed reading copy is
`manual-review/candidate3/hyperannotatR-manual.pdf` (139 pages; 472,995 bytes).
Its SHA-256 is
`f4a2671579899e0c078f83b9fc4001f1a768a97ef2bdcca6ec7c4f550e364843`.

It was generated from the exact source used for the third release check,
`final-check-3/hyperannotatR_0.3.1.tar.gz`, SHA-256
`885217e497a2df441f096be466e88c6d3011aef0920bc35c5b84162b2f1fe668`.
All 155 extracted Rd files were compared byte-for-byte by SHA-256 against
the tar members; all match. No source, API, family membership, example,
author metadata or generated Rd was changed for this PDF remedy.

## Standard output and presentation-only remedy

The baseline R manual already has nine words crossing the physical page edge,
mostly long automatically generated See Also link lists. The standard
candidate-3 manual reproduces those nine clips (138 pages). This is a stock R
manual formatting limitation; it does not invalidate the package checks. The
unmodified standard output remains at `manual-review/candidate3/standard.pdf`,
SHA-256 `a207c5a98a2720824713c25c288f39e225872cc166034ca9a0b20e2360a2f3a2`.

A separate reading copy uses the following preamble in the isolated generated
TeX only:

```tex
\emergencystretch=\hsize
\renewenvironment{SeeAlso}{%
  \begin{Rdsection}{See Also}\raggedright}{\end{Rdsection}}
```

The generated TeX was verified to be identical to its preserved original
except for this preamble. It retains the existing document font, content and
link destinations. Three normal `makeindex`/`pdflatex` passes converged, with
all five auxiliary files (`aux`, `toc`, `idx`, `ind`, `out`) unchanged at the
final pass. The stock manual, baseline diagnostic and superseded candidate-2
artifacts remain preserved separately.

## Navigation, layout and visual verification

The final candidate-3 reading copy passed:

- 139 physical pages, all with matching printed page numbers.
- All 155 contents entries point to the displayed topic page.
- All 1,875 numbered internal links match their displayed page numbers;
  the index begins on page 133, as printed in the contents.
- No invalid named destinations, out-of-page words, narrow-margin words,
  replacement glyphs or unembedded fonts were detected.
- Every page was rendered with Poppler and inspected in 12 labelled contact
  sheets. Pages 1–72 were reviewed together with full-size pages 8, 29 and 38
  for the revised core/control examples and wrapping. A second reviewer
  independently reviewed pages 73–139 and full-size pages 80, 118 and 136
  for long links/usage and dense index columns. Neither review found clipping,
  overlap, missing glyphs or unreadable page transitions.

The standard Rd2pdf build also has internally consistent contents and index
pagination (155 contents entries; 1,865 numbered internal links; index page
132). Its layout clips remain intentionally visible in the preserved output.
Cross-package help destinations are not guaranteed by a standalone manual:
normal TeX warnings for external topics remain in the logs and were not
suppressed. No external help-server navigation is claimed as verified.

## Evidence and reproduction

- `manual-review/candidate3/source-integrity.json`: tar and Rd comparisons.
- `manual-review/candidate3/artifact-integrity.json`: exact generated TeX
  comparison, PDF hashes, all-page render and contact-sheet counts.
- `manual-review/candidate3/convergence-results.json`: three-pass convergence.
- `manual-review/candidate3/review/review-results.json`, `toc-checks.json`,
  `numeric-links.json`: final structural and destination checks.
- `manual-review/candidate3/review/pages/` and `contact-01.png` through
  `contact-12.png`: all 139 rendered pages and visual review sheets.
- `manual-review/candidate3/standard-review/`: standard-output diagnostics.
- `manual-review/candidate3/check-stock-review/` and `stock-comparison.json`:
  completed R CMD check manual comparison and structural checks.
- `manual-review/build-candidate3.py`, `layout-probe.py`, `review.py`, and
  `contact_sheets.py`: external reproducible build/review scripts. The build
  script is intended for a fresh output directory because convergence preserves
  the first generated TeX as its original.

The third `R CMD check` completed with zero errors, zero warnings and one
new-submission NOTE. Its actual stock PDF is preserved at
`final-check-3/hyperannotatR.Rcheck/hyperannotatR-manual.pdf`, SHA-256
`99a792a31d18a1129d3ee38575e229e553456225c4e4085f75d061eb0e8bef02`.
Its extracted text, all 138 page dimensions, every word's text and coordinates,
155 contents entries and 1,865 numbered internal links agree exactly with the
independent standard build from the candidate-3 source. Contents and index
pagination are correct (index page 132), and the same nine baseline clips are
confirmed. The PDF binaries differ; no byte-identity claim is made. The reading
copy and completed-check comparison are fully reviewed and tied to the exact
third candidate source tar.
