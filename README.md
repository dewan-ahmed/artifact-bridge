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
- Enforces a maximum response size.
- Optionally verifies SHA-256 before writing the final file.
- Refuses to overwrite files unless `--force` is passed.
- Uses a temporary file and atomic rename.
- Returns exit code `1` for retrieval or validation failure and `2` for invalid
  arguments.

## Next adapters

- Jira issue attachments.
- GitHub Actions run artifacts.
- Generic object storage and signed URLs.

Adapters will use scoped credentials from environment variables or workload
identity. Credentials will not enter model prompts, logs, reports, fixtures, or
repository history.

## License

MIT
