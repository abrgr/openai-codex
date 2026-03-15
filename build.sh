#!/usr/bin/env bash
set -euo pipefail

CODEX_VERSION=$(curl -sf https://registry.npmjs.org/@openai/codex/latest | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')

docker build \
  --build-arg CODEX_VERSION="$CODEX_VERSION" \
  -t "openai-codex:${CODEX_VERSION}" \
  .
