#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_reset() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt reset

Removes Biotonomy ephemeral state (`.bt/`) and any `specs/**/.lock` files.

Note: v0.1.0 does NOT modify your git working tree.
EOF
    return 0
  fi

  bt_env_load || true
  bt_ensure_dirs

  local state="$BT_PROJECT_ROOT/$BT_STATE_DIR"
  if [[ -d "$state" ]]; then
    rm -rf "$state"
    bt_info "removed $state"
  fi

  local specs_path
  specs_path="$(bt_specs_path)"
  if [[ -d "$specs_path" ]]; then
    find "$specs_path" -type f -name ".lock" -print -delete 2>/dev/null || true
  fi

  bt_notify "bt reset complete in $BT_PROJECT_ROOT"
}

