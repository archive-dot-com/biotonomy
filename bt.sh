#!/usr/bin/env bash
set -euo pipefail

BT_VERSION="0.1.0"

bt_script_dir() {
  local src="${BASH_SOURCE[0]}"
  while [ -h "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}

BT_ROOT="$(bt_script_dir)"

# shellcheck source=/dev/null
source "$BT_ROOT/lib/log.sh"
# shellcheck source=/dev/null
source "$BT_ROOT/lib/path.sh"
# shellcheck source=/dev/null
source "$BT_ROOT/lib/env.sh"
# shellcheck source=/dev/null
source "$BT_ROOT/lib/repo.sh"
# shellcheck source=/dev/null
source "$BT_ROOT/lib/notify.sh"
# shellcheck source=/dev/null
source "$BT_ROOT/lib/codex.sh"
# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"
# shellcheck source=/dev/null
source "$BT_ROOT/lib/gates.sh"

bt_usage() {
  cat <<EOF
biotonomy (bt) v$BT_VERSION

Usage:
  bt <command> [args]

Commands:
  bootstrap  spec  research  implement  review  fix  compound  design  status  gates  reset  pr  ship

Global options:
  -h, --help     Show help
  BT_ENV_FILE    Explicit path to a .bt.env (otherwise read ./.bt.env)
  BT_TARGET_DIR  Operate on this repo dir (sets BT_PROJECT_ROOT); env falls back to \$BT_TARGET_DIR/.bt.env

Examples:
  bt bootstrap
  bt spec 123
  bt status
EOF
}

bt_dispatch() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    -h|--help|help) bt_usage; return 0 ;;
  esac

  bt_env_load || true

  case "$cmd" in
    bootstrap|spec|research|implement|review|fix|compound|design|status|gates|reset|pr|ship) ;;
    *)
      bt_err "unknown command: $cmd"
      bt_usage >&2
      return 2
      ;;
  esac

  local cmd_file="$BT_ROOT/commands/$cmd.sh"
  if [[ "$cmd" == "ship" ]]; then
    cmd_file="$BT_ROOT/commands/pr.sh"
  fi

  if [[ ! -f "$cmd_file" ]]; then
    bt_die "missing command implementation: $cmd_file"
  fi

  # shellcheck source=/dev/null
  source "$cmd_file"

  local fn="bt_cmd_$cmd"
  if [[ "$cmd" == "ship" ]]; then
    fn="bt_cmd_pr"
  fi

  if ! declare -F "$fn" >/dev/null 2>&1; then
    bt_die "command function not found: $fn (in $cmd_file)"
  fi

  "$fn" "$@"
}

bt_dispatch "$@"
