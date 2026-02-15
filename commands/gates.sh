#!/usr/bin/env bash
set -euo pipefail

bt_cmd_gates() {
  local usage="Usage: bt gates [<feature>]

Runs project quality gates (lint, typecheck, test) as configured or auto-detected.
If <feature> is provided, writes results to specs/<feature>/gates.json.
Otherwise, writes to \$BT_PROJECT_ROOT/\$BT_STATE_DIR/state/gates.json."

  local feature=""
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help) echo "$usage"; return 0 ;;
      -*) bt_err "Unknown argument: $1"; echo "$usage"; return 1 ;;
      *) feature="$(bt_require_feature "$1")" ;;
    esac
  fi

  local json_out
  local exit_code=0
  
  # bt_run_gates outputs the JSON to stdout, and exits with non-zero if any gate failed.
  if ! json_out="$(bt_run_gates)"; then
    exit_code=1
  fi

  local out_dir
  if [[ -n "$feature" ]]; then
    out_dir="$(bt_feature_dir "$feature")"
  else
    out_dir="$BT_PROJECT_ROOT/$BT_STATE_DIR/state"
  fi

  mkdir -p "$out_dir"
  printf '%s\n' "$json_out" > "$out_dir/gates.json"
  bt_info "Gate results saved to $out_dir/gates.json"

  return "$exit_code"
}
