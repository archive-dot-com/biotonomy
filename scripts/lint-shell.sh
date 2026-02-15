#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Deterministic output ordering regardless of runner locale.
export LC_ALL=C
export LANG=C

if ! command -v shellcheck >/dev/null 2>&1; then
  if [[ "${BT_LINT_STRICT:-0}" == "1" ]]; then
    echo "lint: shellcheck not found (BT_LINT_STRICT=1); failing" >&2
    exit 1
  fi
  echo "lint: shellcheck not found; skipping (install shellcheck to enable)" >&2
  exit 0
fi

files=()

# Prefer tracked files when running from a git worktree. This avoids glob ordering
# differences and silently skipping new folders.
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r f; do
    files+=("$f")
  done < <(git ls-files -- '*.sh' | sort)
else
  # npm-installed tarballs don't include `.git/`, so fall back to globs.
  shopt -s nullglob
  files+=(bt.sh commands/*.sh lib/*.sh hooks/*.sh scripts/*.sh)
  shopt -u nullglob
  # Normalize ordering.
  mapfile -t files < <(printf '%s\n' "${files[@]}" | sort)
fi

shellcheck -x "${files[@]}"
