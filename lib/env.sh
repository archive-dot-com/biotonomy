#!/usr/bin/env bash
set -euo pipefail

bt__export_kv() {
  local key="$1"
  local val="$2"

  [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 0
  # Export without eval; keep value literal even if it contains spaces/symbols.
  export "$key=$val"
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

    # Allow common `.env` style: `export KEY=VALUE`
    if [[ "$line" =~ ^export[[:space:]]+ ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"
    fi

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
    else
      # Strip trailing inline comments for unquoted values: `KEY=VAL # comment`
      val="${val%%[[:space:]]#*}"
      val="${val%"${val##*[![:space:]]}"}"
    fi

    bt__export_kv "$key" "$val"
  done <"$f"

  export BT_ENV_FILE="$f"
}

bt_env_load() {
  # Optional: run bt from anywhere, but operate on a specific target repo.
  # When set, BT_TARGET_DIR becomes the effective BT_PROJECT_ROOT for all commands.
  if [[ -n "${BT_TARGET_DIR:-}" ]]; then
    local td
    td="$(bt_realpath "$BT_TARGET_DIR")"
    [[ -e "$td" ]] || bt_die "BT_TARGET_DIR does not exist: $BT_TARGET_DIR"
    [[ -d "$td" ]] || bt_die "BT_TARGET_DIR is not a directory: $BT_TARGET_DIR"
    export BT_TARGET_DIR="$td"
  fi

  local env_file="${BT_ENV_FILE:-}"
  if [[ -n "$env_file" ]]; then
    env_file="$(bt_realpath "$env_file")"
    bt_env_load_file "$env_file" || bt_die "failed to load BT_ENV_FILE=$env_file"
  else
    # Prefer project config from the caller's current working directory.
    if [[ -f "$PWD/.bt.env" ]]; then
      bt_env_load_file "$PWD/.bt.env" || bt_die "failed to load env: $PWD/.bt.env"
    # If running with a target repo, fall back to that repo's .bt.env.
    elif [[ -n "${BT_TARGET_DIR:-}" && -f "$BT_TARGET_DIR/.bt.env" ]]; then
      bt_env_load_file "$BT_TARGET_DIR/.bt.env" || bt_die "failed to load env: $BT_TARGET_DIR/.bt.env"
    fi
  fi

  # Defaults
  export BT_PROJECT_ROOT
  if [[ -n "${BT_TARGET_DIR:-}" ]]; then
    BT_PROJECT_ROOT="$BT_TARGET_DIR"
  elif [[ -n "${BT_ENV_FILE:-}" ]]; then
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
