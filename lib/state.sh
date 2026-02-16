#!/usr/bin/env bash
set -euo pipefail

bt_specs_path() {
  printf '%s/%s' "$BT_PROJECT_ROOT" "$BT_SPECS_DIR"
}

bt_feature_dir() {
  local feature="$1"
  printf '%s/%s' "$(bt_specs_path)" "$feature"
}

bt_ensure_dirs() {
  mkdir -p "$(bt_specs_path)" "$BT_PROJECT_ROOT/$BT_STATE_DIR"
}

bt_sanitize_feature() {
  local s="${1:-}"
  # Replace characters not in [A-Za-z0-9._-] with underscore
  s="${s//[^A-Za-z0-9._-]/_}"
  # Ensure it doesn't start with a dot or dash and isn't empty
  if [[ "$s" =~ ^[._-] ]]; then
    s="f$s"
  fi
  if [[ -z "$s" ]]; then
    s="feature"
  fi
  printf '%s\n' "$s"
}

bt_require_feature() {
  local feature="${1:-${BT_FEATURE:-}}"
  [[ -n "$feature" ]] || bt_die "feature required (pass as first arg or set BT_FEATURE)"

  # Apply sanitization if it doesn't already pass validation
  if [[ "$feature" == *"/"* || "$feature" == *".."* || ! "$feature" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
     feature="$(bt_sanitize_feature "$feature")"
  fi

  # Prevent path traversal and keep on-disk state predictable.
  [[ "$feature" != *"/"* ]] || bt_die "invalid feature (must not contain '/'): $feature"
  [[ "$feature" != *".."* ]] || bt_die "invalid feature (must not contain '..'): $feature"
  [[ "$feature" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || bt_die "invalid feature (allowed: A-Z a-z 0-9 . _ -): $feature"
  printf '%s\n' "$feature"
}

bt_progress_append() {
  local feature="$1"
  local msg="$2"
  local dir
  dir="$(bt_feature_dir "$feature")"
  mkdir -p "$dir/history"
  printf '%s %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$msg" >>"$dir/progress.txt"
}

bt_history_write() {
  local feature="$1"
  local stage="$2"
  local content="$3"
  local dir
  dir="$(bt_feature_dir "$feature")"
  mkdir -p "$dir/history"

  local max=0 f base n
  shopt -s nullglob
  for f in "$dir/history/"[0-9][0-9][0-9]-*.md; do
    base="$(basename "$f")"
    n="${base%%-*}"
    [[ "$n" =~ ^[0-9]{3}$ ]] || continue
    ((10#$n > max)) && max=$((10#$n))
  done
  shopt -u nullglob
  n="$((max + 1))"
  printf -v n '%03d' "$n"

  local out="$dir/history/${n}-${stage}.md"
  printf '%s\n' "$content" >"$out"
  printf '%s\n' "$out"
}
