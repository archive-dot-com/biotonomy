#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "lint: shellcheck not found; skipping (install shellcheck to enable)" >&2
  exit 0
fi

shellcheck -x \
  bt.sh \
  commands/*.sh \
  lib/*.sh \
  hooks/*.sh \
  scripts/*.sh

