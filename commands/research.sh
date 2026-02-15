#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_research() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt research <feature>

Runs Codex in full-auto using prompts/research.md and produces specs/<feature>/RESEARCH.md.
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
  mkdir -p "$dir/history"

  local out="$dir/RESEARCH.md"
  bt_codex_available || bt_die "codex required for research (set BT_CODEX_BIN or install codex)"

  bt_info "running codex (read-only) using prompts/research.md -> $out"
  local codex_ec=0 codex_errf
  codex_errf="$(mktemp "${TMPDIR:-/tmp}/bt-codex-research-err.XXXXXX")"
  if ! BT_FEATURE="$feature" bt_codex_exec_read_only "$BT_ROOT/prompts/research.md" "$out" 2>"$codex_errf"; then
    codex_ec=$?
    bt_warn "codex exited non-zero (research): $codex_ec"
  fi

  if [[ ! -f "$out" ]]; then
    local err_tail
    err_tail="$(tail -n 80 "$codex_errf" 2>/dev/null || true)"
    cat >"$out" <<EOF
# Research: $feature

Codex did not create \`$out\`. A stub was generated so the loop can continue.

- codex_exit: $codex_ec
- feature_dir: $dir
- prompt: $BT_ROOT/prompts/research.md
- bt_cmd: bt research $feature

## Codex stderr (tail)

${err_tail:-"(no stderr captured)"}

Next:
- Run Codex against \`$BT_ROOT/prompts/research.md\`
- Capture findings here (patterns, pitfalls, test/lint commands, etc)
EOF
  fi

  rm -f "$codex_errf" || true

  bt_progress_append "$feature" "research: bt research $feature (codex_exit=$codex_ec)"
  bt_history_write "$feature" "research" "$(cat <<EOF
# Research Run: $feature

- when: $(date +'%Y-%m-%d %H:%M:%S')
- bt_cmd: bt research $feature
- prompt: prompts/research.md
- codex_exit: $codex_ec
- output: specs/$feature/RESEARCH.md
EOF
)"
  [[ -f "$out" ]] && bt_info "wrote $out"
  bt_notify "bt research complete for $feature"
}
