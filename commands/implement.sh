#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_implement() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt implement <feature>

Stubbed in v0.1.0: records an implement iteration marker in history/progress.
EOF
    return 0
  fi

  bt_env_load || true
  bt_ensure_dirs

  local feature
  feature="$(bt_require_feature "${1:-}")"

  local dir
  dir="$(bt_feature_dir "$feature")"
  [[ -d "$dir" ]] || bt_die "missing feature dir: $dir (run: bt spec ...)"

  bt_progress_append "$feature" "implement iteration"

  if bt_codex_available; then
    bt_info "running codex (full-auto) using prompts/implement.md"
    bt_codex_exec_full_auto "$BT_ROOT/prompts/implement.md" || bt_warn "codex exited non-zero (implement)"
  else
    bt_warn "codex unavailable; implement is a v0.1.0 stub"
  fi

  bt_info "running quality gates (best-effort)"
  bt_run_gates || bt_warn "gates failed"

  local h
  h="$(bt_history_write "$feature" "implement" "$(cat "$BT_ROOT/prompts/implement.md" 2>/dev/null || echo 'implement prompt missing')")"
  bt_info "wrote history: $h"
  bt_notify "bt implement stub ran for $feature"
}
