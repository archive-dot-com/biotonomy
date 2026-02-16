#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_plan_review() {
  # Feature name might start with - (e.g. bt plan-review -h)
  # but shell parsing might be tricky.
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt plan-review <feature>

Runs Codex in full-auto using prompts/plan-review.md to approve or reject the SPEC/RESEARCH plan.
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

  local out="$dir/PLAN_REVIEW.md"

  if bt_codex_available; then
    bt_info "running codex (full-auto) using prompts/plan-review.md"
    local artifacts_dir codex_logf
    artifacts_dir="$dir/.artifacts"
    mkdir -p "$artifacts_dir"
    codex_logf="$artifacts_dir/codex-plan-review.log"
    : >"$codex_logf"
    if BT_FEATURE="$feature" BT_CODEX_LOG_FILE="$codex_logf" bt_codex_exec_full_auto "$BT_ROOT/prompts/plan-review.md"; then
      :
    else
      bt_die "codex failed (plan-review)"
    fi
  else
    # v0.1.0 stub
    cat <<'EOF' > "$out"
# Plan Review: Stub Approved

Verdict: APPROVED_PLAN
EOF
    bt_info "wrote $out"
  fi

  if [[ ! -f "$out" ]]; then
    bt_die "bt_cmd_plan_review failed: $out was not created"
  fi

  bt_history_write "$feature" "plan-review" "$(cat "$out")"
  bt_notify "bt plan-review complete for $feature"
}
