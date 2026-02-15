#!/usr/bin/env bash
set -euo pipefail

bt__export_kv() {
  local key="$1"
  local val="$2"

  [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 0
  printf -v "$key" '%s' "$val"
  export "$key"
}

bt_env_load_file() {
  local f="$1"
  [[ -f "$f" ]] || return 1

  bt_debug "loading env: $f"

  # Parse KEY=VALUE lines (no eval), ignore comments/blank lines.
  # Supports single/double quoted values, strips surrounding quotes.
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    line="${line#"${line%%[![:space:]]*}"}"

    [[ "$line" == *"="* ]] || continue
    local key="${line%%=*}"
    local val="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"

    if [[ "$val" =~ ^\".*\"$ ]]; then
      val="${val:1:${#val}-2}"
    elif [[ "$val" =~ ^\'.*\'$ ]]; then
      val="${val:1:${#val}-2}"
    fi

    bt__export_kv "$key" "$val"
  done <"$f"

  export BT_ENV_FILE
  BT_ENV_FILE="$f"
}

bt_env_load() {
  local env_file="${BT_ENV_FILE:-}"
  if [[ -n "$env_file" ]]; then
    env_file="$(bt_realpath "$env_file")"
    bt_env_load_file "$env_file" || bt_die "failed to load BT_ENV_FILE=$env_file"
  else
    env_file="$(bt_find_up ".bt.env" "$PWD" 2>/dev/null || true)"
    if [[ -n "$env_file" ]]; then
      bt_env_load_file "$env_file" || bt_die "failed to load env: $env_file"
    fi
  fi

  # Defaults
  export BT_PROJECT_ROOT
  if [[ -n "${BT_ENV_FILE:-}" ]]; then
    BT_PROJECT_ROOT="$(cd "$(dirname "$BT_ENV_FILE")" && pwd)"
  else
    BT_PROJECT_ROOT="$PWD"
  fi

  export BT_SPECS_DIR="${BT_SPECS_DIR:-specs}"
  export BT_STATE_DIR="${BT_STATE_DIR:-.bt}"
  export BT_NOTIFY_HOOK="${BT_NOTIFY_HOOK:-}"
  export BT_GATE_LINT="${BT_GATE_LINT:-}"
  export BT_GATE_TYPECHECK="${BT_GATE_TYPECHECK:-}"
  export BT_GATE_TEST="${BT_GATE_TEST:-}"
}

