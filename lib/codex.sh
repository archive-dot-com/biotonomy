#!/usr/bin/env bash
set -euo pipefail

bt_codex_bin() {
  printf '%s\n' "${BT_CODEX_BIN:-codex}"
}

bt_codex_available() {
  command -v "$(bt_codex_bin)" >/dev/null 2>&1
}

bt_codex_exec_full_auto() {
  local prompt_file="$1"
  if ! bt_codex_available; then
    bt_warn "codex not found; skipping (set BT_CODEX_BIN or install codex)"
    return 0
  fi
  local bin
  bin="$(bt_codex_bin)"
  "$bin" exec --full-auto -C "$BT_PROJECT_ROOT" "$(cat "$prompt_file")"
}

bt_codex_exec_read_only() {
  local prompt_file="$1"
  local out_file="$2"
  if ! bt_codex_available; then
    bt_warn "codex not found; writing stub output to $out_file"
    printf '%s\n' "Codex unavailable; v0.1.0 stub." >"$out_file"
    return 0
  fi
  local bin
  bin="$(bt_codex_bin)"
  "$bin" exec -s read-only -C "$BT_PROJECT_ROOT" -o "$out_file" "$(cat "$prompt_file")"
}

