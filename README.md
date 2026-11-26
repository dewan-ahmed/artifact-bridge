# artifact-bridge

Safe, deterministic artifact retrieval for agents and software factories.

`artifact-bridge` downloads a file without putting credentials into the model
prompt or command arguments. It validates HTTP status, response type, size, and
an optional SHA-256 digest before atomically moving the file into place.

The core is vendor-neutral. Provider adapters can resolve an attachment or
artifact to a download URL, then use the same guarded fetch path.

## Status

Early development. The CLI can change before version 1.0.

## Build

Install the V version in `.v-version`, then run:

```sh
v -prod -o artifact-bridge .
```

## Use

Public artifact:

```sh
artifact-bridge fetch "https://example.com/build.zip" \
  --out build.zip \
  --max-bytes 104857600 \
  --json
```

Authenticated artifact:

```sh
export ARTIFACT_TOKEN="Bearer ..."

artifact-bridge fetch "https://factory.example.com/build.zip" \
  --out build.zip \
  --header-env "Authorization=ARTIFACT_TOKEN"
```

The header value comes from the environment and is never printed. Reports also
remove URL credentials and query parameters.

## Guardrails

- Rejects non-2xx responses.
- Rejects HTML login and error pages by default.
- Enforces a maximum response size, rejecting early when `Content-Length` is
  already too large and stopping mid-stream otherwise.
- Streams the body to a temporary file while hashing it, so memory stays at a
  few MiB regardless of artifact size. A 300 MB download peaks at about 5 MiB
  RSS.
- Optionally verifies SHA-256 before the final file appears.
- Refuses to overwrite files unless `--force` is passed.
- Uses a temporary file and atomic rename, and removes the temporary file on
  every failure.
- Restricts hosts with `--allow-host HOST` (repeatable) or the comma-separated
  `ARTIFACT_BRIDGE_ALLOW_HOSTS` variable. `*.example.com` matches subdomains,
  not `example.com` itself. When a list is set, the first URL and every
  redirect target must match before any request is sent.
- Requires HTTPS whenever `--header-env` is used. Pass `--allow-insecure-http`
  to send credentials over plain HTTP, for example to a local test server.
- Follows at most `--max-redirects N` redirects (default `5`) and refuses an
  HTTPS to HTTP downgrade. `--header-env` headers are sent only to the origin
  (scheme, host, and port) of the URL you passed, so a redirect to a signed
  object-storage URL works without leaking the credential.
- Lists the redirect chain, without credentials or query strings, in the
  `--json` report as `redirects`.
- Returns exit code `1` for retrieval or validation failure and `2` for invalid
  arguments.

## Failure reports

With `--json`, a failure prints a report to stdout before the exit code, so an
agent or CI job can branch on `error.code` instead of parsing stderr:

```json
{
  "ok": false,
  "url": "https://artifacts.example.com/build.zip",
  "path": "build.zip",
  "error": {
    "code": "http_status",
    "message": "unexpected HTTP status 503",
    "retryable": true,
    "http_status": 503
  }
}
```

Successful reports include `"ok": true`. Optional fields (`http_status`,
`max_bytes`, `expected_sha256`, `actual_sha256`, `env_name`) appear only when
they apply. `retryable` is true for timeouts, network errors, HTTP 429, and
HTTP 5xx.

| Code | Meaning |
| --- | --- |
| `invalid_argument` | Bad flag, URL, or allowlist entry (exit code `2` for flags) |
| `credential_env_missing` | A `--header-env` variable is empty or unset |
| `host_not_allowed` | The URL or a redirect target is outside the allowlist |
| `insecure_http` | Credentials over HTTP or an HTTPS to HTTP redirect |
| `unsupported_scheme` | The URL is not `http` or `https` |
| `redirect_limit` | More than `--max-redirects` redirects |
| `redirect_invalid` | A redirect has a missing or invalid `Location` |
| `http_status` | The final response was not `200` |
| `html_response` | The server returned HTML, usually a login page |
| `size_exceeded` | The body is larger than `--max-bytes` |
| `digest_mismatch` | The SHA-256 does not match `--sha256` |
| `output_exists` | The output exists and `--force` was not given |
| `output_dir_missing` | The output directory does not exist |
| `write_failed` | The artifact could not be written or moved into place |
| `timeout` | The request timed out |
| `tls` | TLS or certificate verification failed |
| `network` | Any other connection failure |

## Next adapters

- Jira issue attachments.
- GitHub Actions run artifacts.
- Generic object storage and signed URLs.

Adapters will use scoped credentials from environment variables or workload
identity. Credentials will not enter model prompts, logs, reports, fixtures, or
repository history.

## License

MIT
