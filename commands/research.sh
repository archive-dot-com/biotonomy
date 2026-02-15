#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_research() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt research <feature>

Stubbed in v0.1.0: writes `RESEARCH.md` and a history entry.
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

  local out="$dir/RESEARCH.md"
  if bt_codex_available; then
    bt_info "running codex (full-auto) using prompts/research.md"
    bt_codex_exec_full_auto "$BT_ROOT/prompts/research.md" || bt_warn "codex exited non-zero (research)"
  fi

  if [[ ! -f "$out" ]]; then
    cat >"$out" <<EOF
# Research: $feature

Codex output missing; v0.1.0 stub.

Next:
- Run Codex against \`$BT_ROOT/prompts/research.md\`
- Capture findings here (patterns, pitfalls, test/lint commands, etc)
EOF
  fi

  bt_progress_append "$feature" "research stub wrote RESEARCH.md"
  bt_history_write "$feature" "research" "Wrote RESEARCH.md stub for $feature."
  [[ -f "$out" ]] && bt_info "wrote $out"
  bt_notify "bt research complete for $feature"
}
