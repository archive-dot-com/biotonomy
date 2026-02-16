#!/usr/bin/env bash
set -euo pipefail

bt_package_version() {
  local pkg="$BT_ROOT/package.json"
  if [[ -f "$pkg" ]]; then
    awk -F '"' '/"version"[[:space:]]*:/ { print $4; exit }' "$pkg"
    return 0
  fi
  return 1
}

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
BT_VERSION="$(bt_package_version 2>/dev/null || true)"
BT_VERSION="${BT_VERSION:-0.1.0}"

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
  bt [--target <path>] <command> [args]

Commands:
  bootstrap  spec  research  plan-review  implement  review  fix  loop  compound  design  status  gates  reset  pr  ship

Global options:
  -h, --help     Show help
  --target <p>   Operate on target project root for this invocation (sets BT_TARGET_DIR)
  BT_ENV_FILE    Explicit path to a .bt.env (otherwise read ./.bt.env)
  BT_TARGET_DIR  Operate on this repo dir (sets BT_PROJECT_ROOT); env falls back to \$BT_TARGET_DIR/.bt.env

Examples:
  bt bootstrap
  bt spec 123
  bt status
  bt --target /path/to/repo status
EOF
}

bt_dispatch() {
  # Global argv parsing (kept intentionally small; this is bash, not a full CLI framework).
  # We support:
  # - bt --target <path> <command> ...
  # - bt <command> ... --target <path> ...
  # - bt --target=<path> <command> ...
  local rest=()
  local target_arg=""
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --target)
        [[ $# -ge 2 ]] || bt_die "--target requires a value"
        target_arg="${2:-}"
        shift 2
        ;;
      --target=*)
        target_arg="${1#--target=}"
        shift
        ;;
      *)
        rest+=("$1")
        shift
        ;;
    esac
  done

  if [[ -n "$target_arg" ]]; then
    export BT_TARGET_DIR="$target_arg"
  fi

  set -- "${rest[@]}"

  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    -h|--help|help)
      if [[ $# -gt 0 ]]; then
        # bt help <cmd>
        cmd="$1"
        shift
        local cmd_file="$BT_ROOT/commands/$cmd.sh"
        if [[ "$cmd" == "ship" ]]; then cmd_file="$BT_ROOT/commands/pr.sh"; fi
        if [[ -f "$cmd_file" ]]; then
          # shellcheck source=/dev/null
          source "$cmd_file"
          local safe_cmd="${cmd//-/_}"
          local fn="bt_${safe_cmd}_usage"
          if [[ "$cmd" == "ship" ]]; then fn="bt_pr_usage"; fi
          if declare -F "$fn" >/dev/null 2>&1; then
            "$fn"
            return 0
          fi
        fi
      fi
      bt_usage; return 0 ;;
  esac

  bt_env_load || true

  case "$cmd" in
    bootstrap|spec|research|plan-review|implement|review|fix|loop|compound|design|status|gates|reset|pr|ship) ;;
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

  local safe_cmd="${cmd//-/_}"
  local fn="bt_cmd_$safe_cmd"
  if [[ "$cmd" == "ship" ]]; then
    fn="bt_cmd_pr"
  fi

  # Log for debugging
  # bt_info "dispatching to $fn"

  if ! declare -F "$fn" >/dev/null 2>&1; then
    bt_die "command function not found: $fn (in $cmd_file)"
  fi

  "$fn" "$@"
}

bt_dispatch "$@"
