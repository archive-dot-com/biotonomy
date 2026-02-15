#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_implement() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt implement <feature>

Runs Codex in full-auto using prompts/implement.md, then runs quality gates.
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

  bt_progress_append "$feature" "implement: bt implement $feature (starting)"

  local codex_ec=0
  if bt_codex_available; then
    bt_info "running codex (full-auto) using prompts/implement.md"
    if ! BT_FEATURE="$feature" bt_codex_exec_full_auto "$BT_ROOT/prompts/implement.md"; then
      codex_ec=$?
      bt_warn "codex exited non-zero (implement): $codex_ec"
    fi
  else
    codex_ec=127
    bt_warn "codex unavailable; implement is a v0.1.0 stub"
  fi

  bt_info "running quality gates"
  local gates_ok=1
  if ! bt_run_gates; then
    gates_ok=0
    bt_progress_append "$feature" "quality gates failed"
    bt_notify "bt implement gates FAILED for $feature"
  fi

  local h
  h="$(bt_history_write "$feature" "implement" "$(cat <<EOF
# Implement Run: $feature

- when: $(date +'%Y-%m-%d %H:%M:%S')
- bt_cmd: bt implement $feature
- prompt: prompts/implement.md
- codex_exit: $codex_ec
- gates: $([[ "$gates_ok" == "1" ]] && echo PASS || echo FAIL)
EOF
)")"
  bt_info "wrote history: $h"
  bt_notify "bt implement complete for $feature"

  [[ "$gates_ok" == "1" ]] || return 1
}
