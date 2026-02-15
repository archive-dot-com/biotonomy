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

bt_require_feature() {
  local feature="${1:-${BT_FEATURE:-}}"
  [[ -n "$feature" ]] || bt_die "feature required (pass as first arg or set BT_FEATURE)"
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

  local n
  n="$(ls -1 "$dir/history" 2>/dev/null | wc -l | tr -d ' ')"
  n="$((n + 1))"
  printf -v n '%03d' "$n"

  local out="$dir/history/${n}-${stage}.md"
  printf '%s\n' "$content" >"$out"
  printf '%s\n' "$out"
}

