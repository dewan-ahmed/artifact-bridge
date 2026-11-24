#!/usr/bin/env sh
set -eu

export ARTIFACT_TOKEN="replace-me"

artifact-bridge fetch "https://factory.example.com/artifacts/build.zip" \
  --out build.zip \
  --header-env "Authorization=ARTIFACT_TOKEN" \
  --max-bytes 104857600 \
  --json
