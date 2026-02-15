#!/usr/bin/env bash
set -euo pipefail

bt_realpath() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$p" 2>/dev/null && return 0
  fi

  # Best-effort fallback: not fully resolving .. or symlinks.
  case "$p" in
    /*) printf '%s\n' "$p" ;;
    *) printf '%s/%s\n' "$(pwd)" "$p" ;;
  esac
}

bt_find_up() {
  local name="$1"
  local start="${2:-$PWD}"

  local d
  d="$(cd "$start" && pwd)"

  while :; do
    if [[ -e "$d/$name" ]]; then
      printf '%s\n' "$d/$name"
      return 0
    fi
    [[ "$d" == "/" ]] && return 1
    d="$(dirname "$d")"
  done
}
