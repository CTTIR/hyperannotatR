Canonical-JSON accept vectors copied verbatim from qupflowR
(`inst/schema/protocol/v1/fixtures/canonical/`, revision
f100973). Each `<case>.json` must canonicalise to the bytes of
`<case>.canonical` (SHA-256 in `<case>.sha256`). hyperannotatR's canonical JSON is
byte-identical to qupflowR's for documents of strings, booleans, null and
integers up to 2^53 - 1 in magnitude; it additionally writes fractional
numbers (shortest of 15-17 significant digits), which qupflowR rejects.

Licence: qupflowR is licensed GPL (>= 3). These vectors are copyright 2026
Raban Heller, their sole author, who also licenses these copies under
hyperannotatR's MIT licence (see `LICENSE`).
