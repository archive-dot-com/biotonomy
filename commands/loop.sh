#!/usr/bin/env bash
set -euo pipefail

# biotonomy loop command
# Implement -> Review -> Fix loop until review is APPROVED and gates pass

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_loop_usage() {
  cat <<EOF
Usage: bt loop <feature> [options]

Repeatedly runs implement/review/fix until review returns Verdict: APPROVED 
and quality gates pass.

Options:
  --max-iterations <n>  Maximum number of retry loops (default: 5)
  -h, --help            Show this help
EOF
}

bt_cmd_loop() {
  local max_iter=5
  local feature=""

  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      -h|--help) bt_loop_usage; return 0 ;;
      --max-iterations) max_iter="${2:-}"; shift 2 ;;
      -*)
        bt_err "unknown flag: $1"
        return 2
        ;;
      *)
        feature="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$feature" ]]; then
    bt_err "feature name is required"
    return 2
  fi

  bt_env_load || true
  bt_ensure_dirs

  bt_info "starting loop for: $feature (max iterations: $max_iter)"

  # Source required commands so we can call them directly
  # shellcheck source=/dev/null
  source "$BT_ROOT/commands/implement.sh"
  # shellcheck source=/dev/null
  source "$BT_ROOT/commands/review.sh"
  # shellcheck source=/dev/null
  source "$BT_ROOT/commands/fix.sh"

  local iter=0
  local review_file
  review_file="$(bt_feature_dir "$feature")/REVIEW.md"

  while [[ "$iter" -lt "$max_iter" ]]; do
    iter=$((iter + 1))
    bt_info "--- Iteration $iter / $max_iter ---"

    # 1. Run Implement (or Fix on subsequent turns)
    if [[ "$iter" -eq 1 ]]; then
      bt_info "running implement..."
      if ! bt_cmd_implement "$feature"; then
        bt_warn "implement or gates failed on iter $iter"
      fi
    else
      bt_info "running fix..."
      if ! bt_cmd_fix "$feature"; then
        bt_warn "fix or gates failed on iter $iter"
      fi
    fi

    # 2. Run Review
    bt_info "running review..."
    if ! bt_cmd_review "$feature"; then
       bt_err "review process failed"
       return 1
    fi

    # 3. Check Verdict
    if [[ ! -f "$review_file" ]]; then
       bt_err "REVIEW.md missing after review command"
       return 1
    fi

    local verdict
    verdict="$(grep "Verdict:" "$review_file" | head -n 1 | awk '{print $2}' || true)"
    bt_info "verdict: $verdict"

    # 4. Check Gates
    local gates_ok=1
    if ! bt_run_gates; then
      gates_ok=0
      bt_info "gates: FAIL"
    else
      bt_info "gates: PASS"
    fi

    if [[ "$verdict" == "APPROVED" && "$gates_ok" == "1" ]]; then
      bt_info "Loop successful! Verdict APPROVED and Gates PASS."
      return 0
    fi

    bt_info "Verdict is $verdict (or gates failed); looping..."
  done

  bt_err "Loop reached max iterations ($max_iter) without approval."
  return 1
}
