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

  # Pure-bash lexical fallback when neither `realpath` nor `python3` is available.
  # Resolves relative paths and normalizes "."/".." segments without requiring
  # filesystem existence checks.
  local abs
  case "$p" in
    /*) abs="$p" ;;
    *) abs="$(pwd)/$p" ;;
  esac

  local IFS='/'
  local -a parts stack
  read -r -a parts <<< "$abs"

  local seg
  for seg in "${parts[@]}"; do
    [[ -z "$seg" || "$seg" == "." ]] && continue
    if [[ "$seg" == ".." ]]; then
      if ((${#stack[@]} > 0)); then
        unset 'stack[${#stack[@]}-1]'
      fi
      continue
    fi
    stack+=("$seg")
  done

  if ((${#stack[@]} == 0)); then
    printf '/\n'
    return 0
  fi

  printf '/%s' "${stack[0]}"
  local i
  for ((i = 1; i < ${#stack[@]}; i++)); do
    printf '/%s' "${stack[$i]}"
  done
  printf '\n'
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
