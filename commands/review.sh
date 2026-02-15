#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_review() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt review <feature>

Runs Codex in read-only using prompts/review.md and produces specs/<feature>/REVIEW.md.
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
  local codex_ec=0
  if ! BT_FEATURE="$feature" bt_codex_exec_read_only "$BT_ROOT/prompts/review.md" "$out"; then
    codex_ec=$?
    bt_warn "codex exited non-zero (review): $codex_ec"
  fi

  if [[ ! -f "$out" ]]; then
    cat >"$out" <<EOF
# Review: $feature

Verdict: NEEDS_CHANGES

Codex did not produce \`$out\`. A stub was generated so the loop can continue.

- codex_exit: $codex_ec
- feature_dir: $dir
- prompt: $BT_ROOT/prompts/review.md
- bt_cmd: bt review $feature
EOF
  elif ! grep -qi '^Verdict:' "$out" 2>/dev/null; then
    local tmp artifacts_dir
    artifacts_dir="$dir/.artifacts"
    mkdir -p "$artifacts_dir"
    # Deterministic temp path to keep outputs reproducible and scoped to the feature dir.
    tmp="$artifacts_dir/review.rewrite.tmp.md"
    cat >"$tmp" <<EOF
# Review: $feature

Verdict: NEEDS_CHANGES

Codex output was missing the required \`Verdict:\` line. Content preserved below.

EOF
    cat "$out" >>"$tmp" 2>/dev/null || true
    mv "$tmp" "$out"
  fi

  bt_progress_append "$feature" "review: bt review $feature (codex_exit=$codex_ec)"
  bt_history_write "$feature" "review" "$(cat <<EOF
# Review Run: $feature

- when: $(date +'%Y-%m-%d %H:%M:%S')
- bt_cmd: bt review $feature
- prompt: prompts/review.md
- codex_exit: $codex_ec
- output: specs/$feature/REVIEW.md
EOF
)"
  bt_info "wrote $out"
  bt_notify "bt review complete for $feature"
}
