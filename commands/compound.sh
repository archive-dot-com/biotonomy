#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_compound() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt compound <feature>

Stubbed in v0.1.0: writes a learnings file under `learnings/`.
EOF
    return 0
  fi

  bt_env_load || true
  bt_ensure_dirs

  local feature
  feature="$(bt_require_feature "${1:-}")"

  mkdir -p "$BT_PROJECT_ROOT/learnings"
  local out="$BT_PROJECT_ROOT/learnings/$feature.md"
  cat >"$out" <<EOF
# Learnings: $feature

This is a v0.1.0 stub.
EOF

  bt_progress_append "$feature" "compound stub wrote learnings/$feature.md"
  bt_history_write "$feature" "compound" "Wrote learnings for $feature."
  bt_info "wrote $out"
  bt_notify "bt compound complete for $feature"
}

