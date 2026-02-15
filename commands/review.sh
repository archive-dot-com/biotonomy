#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_review() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt review <feature>

Stubbed in v0.1.0: writes `REVIEW.md` and a history entry.
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

  local out="$dir/REVIEW.md"
  bt_codex_exec_read_only "$BT_ROOT/prompts/review.md" "$out" || bt_warn "codex exited non-zero (review)"

  if ! grep -qi '^Verdict:' "$out" 2>/dev/null; then
    cat >"$out" <<EOF
# Review: $feature

Verdict: NEEDS_CHANGES

Codex output missing; v0.1.0 stub. Replace with real findings.
EOF
  fi

  bt_progress_append "$feature" "review stub wrote REVIEW.md"
  bt_history_write "$feature" "review" "$(cat "$BT_ROOT/prompts/review.md" 2>/dev/null || echo 'review prompt missing')"
  bt_info "wrote $out"
  bt_notify "bt review complete for $feature"
}
