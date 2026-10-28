# Send a typed control command

Send one `annotatr-control-v1` operation. The command is a list with
`operation` (one of
[`at_control_capabilities()`](https://cttir.github.io/hyperannotatR/reference/at_control_capabilities.md)`$operations`),
`payload` (a list) and `expected_revision` (the `state_revision` the
command is based on). `request_id` and `idempotency_key` are generated
when absent and `content_sha256` is always computed from the canonical
payload. A stale revision raises an `at_conflict_error`
(`REVISION_CONFLICT`); re-sending the same command with the same
idempotency key returns the original result (`replayed = TRUE` in the
response) instead of applying it twice. The service keeps the most
recent 1000 request records; a replay of an older key raises
`IDEMPOTENCY_EXPIRED` instead of executing again, and a large stored
response (for example a mask preview PNG) is replayed in compact form
with `response_truncated = TRUE`. `close` is the only operation that
does not check `expected_revision`. Errors carry the same condition
class as the corresponding local call.

## Usage

``` r
at_control_command(handle, command, call = rlang::caller_env())
```

## Arguments

- handle:

  An `at_control_handle`.

- command:

  A list with `operation`, `payload`, `expected_revision` and optionally
  `request_id`, `idempotency_key` and `extensions`.

- call:

  The calling environment, for error reporting.

## Value

The response `data` (a list) with the response envelope in
`attr(, "response")`.

## See also

[`at_control_request_status()`](https://cttir.github.io/hyperannotatR/reference/at_control_request_status.md)

Other control:
[`at_control_capabilities()`](https://cttir.github.io/hyperannotatR/reference/at_control_capabilities.md),
[`at_control_close()`](https://cttir.github.io/hyperannotatR/reference/at_control_close.md),
[`at_control_connect()`](https://cttir.github.io/hyperannotatR/reference/at_control_connect.md),
[`at_control_events()`](https://cttir.github.io/hyperannotatR/reference/at_control_events.md),
[`at_control_request_status()`](https://cttir.github.io/hyperannotatR/reference/at_control_request_status.md),
[`at_control_start()`](https://cttir.github.io/hyperannotatR/reference/at_control_start.md),
[`at_control_state()`](https://cttir.github.io/hyperannotatR/reference/at_control_state.md),
[`at_control_stop()`](https://cttir.github.io/hyperannotatR/reference/at_control_stop.md)

## Examples

``` r
h <- at_control_start(at_example_session(3), serve = FALSE)
st <- at_control_state(h)
at_control_command(h, list(operation = "context.goto", payload = list(queue_index = 2),
                           expected_revision = st$state_revision))
#> $queue_index
#> [1] 2
#> 
#> $entry_id
#> [1] "entry_at_23154e8c45c1_000000004"
#> 
#> $image_id
#> [1] "sha256:3fa00078c93c3a7d"
#> 
#> $annotation_revision
#> [1] "sha256:77f4c6171f87df36369045976bf6354c68d0041f4b136ac99fd91ab2e1100246"
#> 
#> attr(,"response")
#> attr(,"response")$protocol
#> [1] "annotatr-control-v1"
#> 
#> attr(,"response")$protocol_version
#> [1] "1.1"
#> 
#> attr(,"response")$request_id
#> [1] "request-dcce88d2-8c12-4873-997a-c6b3229bfdef"
#> 
#> attr(,"response")$instance_id
#> [1] "instance-5bfbef97-caf0-452e-83d1-b2b1fc0e4839"
#> 
#> attr(,"response")$state_revision
#> [1] "1"
#> 
#> attr(,"response")$event_cursor
#> [1] "instance-5bfbef97-caf0-452e-83d1-b2b1fc0e4839:2"
#> 
#> attr(,"response")$warnings
#> list()
#> 
at_control_stop(h)
```
