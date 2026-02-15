#!/usr/bin/env bash
set -euo pipefail

bt_cmd_bootstrap() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt bootstrap

Creates a project-local `.bt.env` and scaffolds required folders (`specs/`, `.bt/`).
EOF
    return 0
  fi

  local env_path="$PWD/.bt.env"
  if [[ -f "$env_path" ]]; then
    bt_info "found existing .bt.env"
  else
    cat >"$env_path" <<'EOF'
# Biotonomy project config (loaded by bt)

# Where feature state lives.
BT_SPECS_DIR=specs

# Where ephemeral state lives (locks, caches, etc).
BT_STATE_DIR=.bt

# Optional: point this at an executable script to receive notifications.
# Example: BT_NOTIFY_HOOK=./hooks/telegram.sh
BT_NOTIFY_HOOK=

# Optional: override quality gates (commands). Empty means "auto-detect" (future).
BT_GATE_LINT=
BT_GATE_TYPECHECK=
BT_GATE_TEST=
EOF
    bt_info "wrote $env_path"
  fi

  mkdir -p "$PWD/specs" "$PWD/.bt" "$PWD/hooks"
  bt_info "ensured dirs: specs/ .bt/ hooks/"

  bt_notify "bt bootstrap complete in $PWD"
}

