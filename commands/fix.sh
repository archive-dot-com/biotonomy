#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_fix() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt fix <feature>

Stubbed in v0.1.0: records a fix iteration marker in history/progress.
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

  bt_progress_append "$feature" "fix iteration"

  if bt_codex_available; then
    bt_info "running codex (full-auto) using prompts/fix.md"
    bt_codex_exec_full_auto "$BT_ROOT/prompts/fix.md" || bt_warn "codex exited non-zero (fix)"
  else
    bt_warn "codex unavailable; fix is a v0.1.0 stub"
  fi

  bt_info "running quality gates"
  local gates_ok=1
  if ! bt_run_gates; then
    gates_ok=0
    bt_progress_append "$feature" "quality gates failed"
    bt_notify "bt fix gates FAILED for $feature"
  fi

  local h
  h="$(bt_history_write "$feature" "fix" "$(cat "$BT_ROOT/prompts/fix.md" 2>/dev/null || echo 'fix prompt missing')")"
  bt_info "wrote history: $h"
  bt_notify "bt fix complete for $feature"

  [[ "$gates_ok" == "1" ]] || return 1
}
