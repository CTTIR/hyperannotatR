# Start the local control service

Start an `annotatr-control-v1` service for a session so that a partner
process (for example qupflowR) can read state and events and send typed
commands. Nothing is started unless this function is called with
`control = "loopback"`. The service binds only to `127.0.0.1`, requires
a random 256-bit bearer token that expires after `ttl_seconds`, rejects
browser-origin requests, enforces JSON size and path limits, and
resolves file references only below `root`. There is no endpoint that
evaluates code.

## Usage

``` r
at_control_start(
  session,
  control = "loopback",
  host = "127.0.0.1",
  port = 0L,
  ttl_seconds = 900L,
  root = NULL,
  token_file = NULL,
  read_only = FALSE,
  max_body_bytes = 1048576L,
  serve = TRUE,
  call = rlang::caller_env()
)
```

## Arguments

- session:

  What to control: an
  [annot_session](https://cttir.github.io/hyperannotatR/reference/hyperannotatR-classes.md)
  (or anything
  [`at_annotate()`](https://cttir.github.io/hyperannotatR/reference/at_annotate.md)
  accepts).

- control:

  Must be `"loopback"`.

- host:

  Must be `"127.0.0.1"`.

- port:

  Port; `0` picks a random free port.

- ttl_seconds:

  Token lifetime in seconds (1 to 86400).

- root:

  Directory for payload references, exports, training exports and the
  lifecycle manifest; defaults to `<session out_dir>/control`.

- token_file:

  Optional path of a new file to receive the token (for a client
  process). It must not exist yet.

  The token needs a cryptographically secure random source
  (`/dev/urandom`, or the openssl package where there is none, as on
  Windows); without one the service is not started
  (`CAPABILITY_UNAVAILABLE`).

- read_only:

  Logical; refuse annotation mutations.

- max_body_bytes:

  Maximum request body size.

- serve:

  Logical; start the HTTP listener. With `FALSE` only in-process calls
  through the handle are possible (useful in tests).

- call:

  The calling environment, for error reporting.

## Value

An `at_control_handle` (a list with `kind = "local"`, `instance_id`,
`session_id`, `host`, `port`, `pid`, `manifest`, `expires_at`); its
print method never shows the token.

## Details

The token is never written into URLs, logs, downloads, manifests or RDS
files. In-process calls use the returned handle; a separate client
process reads the token from `token_file`, which is created exclusively
with owner-only permissions (on Windows, file modes are not enforced;
keep the file in a directory only the user can read). A sanitised
lifecycle manifest `annotatr-control-<instance_id>.json` is written to
`root` at start and rewritten when the service stops.

The service stops itself when the token expires: either when the expiry
timer runs or, if a request arrives first (for example after the
computer slept), on that request. Error messages sent to clients never
contain absolute local paths. Request bodies whose declared
`Content-Length` exceeds `max_body_bytes`, and requests that fail the
Host, Origin or token checks, are refused before the body is read (a
chunked body without `Content-Length` is buffered by httpuv and then
refused).

Two options bound work done for clients:
`hyperannotatR.control_mask_max_pixels` (default `4096^2`) is the
largest mask `mask.preview` builds (without a `level` it picks the
finest pyramid level within the budget), and
`hyperannotatR.control_hash_max_bytes` (default 256 MiB) is the largest
queue entry whose content id `GET /v1/state` computes before the entry
is visited (larger entries report `image_id: null` until then).

## See also

[`at_control_stop()`](https://cttir.github.io/hyperannotatR/reference/at_control_stop.md),
[`at_control_command()`](https://cttir.github.io/hyperannotatR/reference/at_control_command.md),
[`at_app()`](https://cttir.github.io/hyperannotatR/reference/at_app.md)

Other control:
[`at_control_capabilities()`](https://cttir.github.io/hyperannotatR/reference/at_control_capabilities.md),
[`at_control_close()`](https://cttir.github.io/hyperannotatR/reference/at_control_close.md),
[`at_control_command()`](https://cttir.github.io/hyperannotatR/reference/at_control_command.md),
[`at_control_connect()`](https://cttir.github.io/hyperannotatR/reference/at_control_connect.md),
[`at_control_events()`](https://cttir.github.io/hyperannotatR/reference/at_control_events.md),
[`at_control_request_status()`](https://cttir.github.io/hyperannotatR/reference/at_control_request_status.md),
[`at_control_state()`](https://cttir.github.io/hyperannotatR/reference/at_control_state.md),
[`at_control_stop()`](https://cttir.github.io/hyperannotatR/reference/at_control_stop.md)

## Examples

``` r
h <- at_control_start(at_example_session(2), serve = FALSE)
at_control_state(h)$state_revision
#> [1] "0"
at_control_stop(h)
```
