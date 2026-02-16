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
      --max-iterations)
        if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == -* ]]; then
          bt_err "--max-iterations requires a value"
          return 2
        fi
        max_iter="$2"
        shift 2
        ;;
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

  if ! [[ "$max_iter" =~ ^[1-9][0-9]*$ ]]; then
    bt_err "--max-iterations must be a positive integer"
    return 2
  fi

  bt_env_load || true
  bt_ensure_dirs

  local feat_dir
  feat_dir="$(bt_feature_dir "$feature")"
  local plan_review="$feat_dir/PLAN_REVIEW.md"
  if [[ ! -f "$plan_review" ]] || ! grep -qiE "Verdict:.*(APPROVE_PLAN|APPROVED_PLAN)" "$plan_review"; then
    bt_err "missing or unapproved $plan_review"
    bt_err "run: bt plan-review $feature"
    bt_die "loop hard-fails without approved PLAN_REVIEW verdict before implement/review"
  fi

  bt_info "starting loop for: $feature (max iterations: $max_iter)"

  bt_info "running preflight gates..."
  if ! bt_run_gates; then
    bt_err "preflight gates failed; aborting before implement/review"
    return 1
  fi
  bt_info "preflight gates: PASS"

  # Source required commands so we can call them directly
  # shellcheck source=/dev/null
  source "$BT_ROOT/commands/implement.sh"
  # shellcheck source=/dev/null
  source "$BT_ROOT/commands/review.sh"
  # shellcheck source=/dev/null
  source "$BT_ROOT/commands/fix.sh"

  local iter=0
  local review_file
  local feat_dir
  feat_dir="$(bt_feature_dir "$feature")"
  review_file="$feat_dir/REVIEW.md"
  local history_dir="$feat_dir/history"
  local progress_file="$feat_dir/loop-progress.json"

  # Initialize progress
  mkdir -p "$history_dir"
  cat > "$progress_file" <<EOF
{
  "feature": "$feature",
  "maxIterations": $max_iter,
  "completedIterations": 0,
  "result": "in-progress",
  "iterations": []
}
EOF

  # Ensure subcommands return non-zero instead of exiting the entire loop process.
  export BT_DIE_MODE="return"

  while [[ "$iter" -lt "$max_iter" ]]; do
    iter=$((iter + 1))
    bt_info "--- Iteration $iter / $max_iter ---"

    # 1. Run Implement on every iteration
    # Note: bt_cmd_implement already runs gates internally.
    bt_info "running implement..."
    if bt_cmd_implement "$feature"; then
      :
    else
      bt_err "implement failed on iter $iter; aborting loop"
      python3 - <<PY
import json
p = "$progress_file"
with open(p, 'r') as f:
    d = json.load(f)
d['completedIterations'] = $iter
d['result'] = 'implement-failed'
d.setdefault('iterations', []).append({
    "iteration": $iter,
    "implementStatus": "FAIL",
    "reviewStatus": "SKIP",
    "fixStatus": "SKIP",
    "verdict": "",
    "gates": "FAIL",
    "historyFile": ""
})
with open(p, 'w') as f:
    json.dump(d, f, indent=2)
PY
      return 1
    fi

    # 2. Run Review
    bt_info "running review..."
    if bt_cmd_review "$feature"; then
       :
    else
       bt_err "review process failed"
       return 1
    fi

    # 3. Check Verdict
    if [[ ! -f "$review_file" ]]; then
       bt_err "REVIEW.md missing after review command"
       return 1
    fi

    local verdict
    verdict="$(awk '/^Verdict:/{print toupper($2); exit}' "$review_file" | tr -d '\r' || true)"
    bt_info "verdict: $verdict"

    # 4. Final Gate Check for convergence
    # We use the gates result from the last command that ran them (implement/fix).
    # bt_cmd_implement/fix return non-zero if gates fail, but we capture the status.
    # We call bt_run_gates here just to be sure of the final state post-review.
    local gates_ok=1
    if ! bt_run_gates; then
      gates_ok=0
      bt_info "gates: FAIL"
    else
      bt_info "gates: PASS"
    fi

    local fix_status="SKIP"
    if [[ "$verdict" == "NEEDS_CHANGES" ]]; then
      bt_info "running fix..."
      # Note: bt_cmd_fix already runs gates internally.
      if bt_cmd_fix "$feature"; then
        fix_status="PASS"
      else
        fix_status="FAIL"
        bt_err "fix failed after iter $iter review; aborting loop"
        return 1
      fi
    fi

    # Record iteration
    local ts
    ts="$(date +%Y-%m-%dT%H%M%S%z)"
    local iter_padded
    iter_padded="$(printf "%03d" "$iter")"
    local hist_file="$history_dir/$ts-loop-iter-$iter_padded.md"
    cp "$review_file" "$hist_file"

    # Update progress.json
    python3 - <<PY
import json, sys
p = "$progress_file"
with open(p, 'r') as f:
    data = json.load(f)
data['completedIterations'] = $iter
data['iterations'].append({
    "iteration": $iter,
    "implementStatus": "PASS",
    "reviewStatus": "PASS",
    "fixStatus": "$fix_status",
    "verdict": "$verdict",
    "gates": "PASS" if "$gates_ok" == "1" else "FAIL",
    "historyFile": "$hist_file"
})
with open(p, 'w') as f:
    json.dump(data, f, indent=2)
PY

    if [[ ( "$verdict" == "APPROVE" || "$verdict" == "APPROVED" ) && "$gates_ok" == "1" ]]; then
      python3 -c "import json; p='$progress_file'; d=json.load(open(p)); d['result']='success'; json.dump(d, open(p, 'w'), indent=2)"
      bt_info "Loop successful! Verdict $verdict and Gates PASS."
      return 0
    fi

    bt_info "Verdict is $verdict (or gates failed); looping..."
  done

  python3 -c "import json; p='$progress_file'; d=json.load(open(p)); d['result']='max-iterations-exceeded'; json.dump(d, open(p, 'w'), indent=2)"
  bt_err "Loop reached max iterations ($max_iter) without approval."
  return 1
}
