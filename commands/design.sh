#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_design() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt design <feature>

Stubbed in v0.1.0: records a design iteration marker in history/progress.
EOF
    return 0
  fi

  bt_env_load || true
  bt_ensure_dirs

  local feature
  feature="$(bt_require_feature "${1:-}")"

  local dir
  dir="$(bt_feature_dir "$feature")"
  mkdir -p "$dir/history"

  bt_progress_append "$feature" "design stub iteration"
  bt_history_write "$feature" "design" "Design iteration placeholder for $feature."
  bt_info "design stub recorded for $feature"
  bt_notify "bt design stub ran for $feature"
}

