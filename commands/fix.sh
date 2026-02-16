#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_fix() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt fix <feature>

Runs Codex in full-auto using prompts/fix.md, then runs quality gates.
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

  bt_progress_append "$feature" "fix: bt fix $feature (starting)"

  local codex_ec=0
  if bt_codex_available; then
    bt_info "running codex (full-auto) using prompts/fix.md"
    local artifacts_dir codex_logf
    artifacts_dir="$dir/.artifacts"
    mkdir -p "$artifacts_dir"
    codex_logf="$artifacts_dir/codex-fix.log"
    : >"$codex_logf"
    if BT_FEATURE="$feature" BT_CODEX_LOG_FILE="$codex_logf" bt_codex_exec_full_auto "$BT_ROOT/prompts/fix.md"; then
      codex_ec=0
    else
      codex_ec=$?
      bt_warn "codex exited non-zero (fix): $codex_ec"
      bt_die "codex failed (fix), stopping."
      return 1
    fi
  else
    codex_ec=127
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
  h="$(bt_history_write "$feature" "fix" "$(cat <<EOF
# Fix Run: $feature

- when: $(date +'%Y-%m-%d %H:%M:%S')
- bt_cmd: bt fix $feature
- prompt: prompts/fix.md
- codex_exit: $codex_ec
- gates: $([[ "$gates_ok" == "1" ]] && echo PASS || echo FAIL)
EOF
)")"
  bt_info "wrote history: $h"
  bt_notify "bt fix complete for $feature"

  [[ "$gates_ok" == "1" ]] || return 1
}
