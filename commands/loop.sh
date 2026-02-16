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

  while [[ "$iter" -lt "$max_iter" ]]; do
    iter=$((iter + 1))
    bt_info "--- Iteration $iter / $max_iter ---"

    # 1. Run Implement on every iteration
    bt_info "running implement..."
    if ! bt_cmd_implement "$feature"; then
      bt_warn "implement or gates failed on iter $iter"
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
    "verdict": "$verdict",
    "gates": "PASS" if "$gates_ok" == "1" else "FAIL",
    "historyFile": "$hist_file"
})
with open(p, 'w') as f:
    json.dump(data, f, indent=2)
PY

    if [[ "$verdict" == "APPROVED" && "$gates_ok" == "1" ]]; then
      python3 -c "import json; p='$progress_file'; d=json.load(open(p)); d['result']='success'; json.dump(d, open(p, 'w'), indent=2)"
      bt_info "Loop successful! Verdict APPROVED and Gates PASS."
      return 0
    fi

    if [[ "$verdict" == "NEEDS_CHANGES" ]]; then
      bt_info "running fix..."
      if ! bt_cmd_fix "$feature"; then
        bt_warn "fix or gates failed after iter $iter review"
      fi
    fi

    bt_info "Verdict is $verdict (or gates failed); looping..."
  done

  python3 -c "import json; p='$progress_file'; d=json.load(open(p)); d['result']='max-iterations-exceeded'; json.dump(d, open(p, 'w'), indent=2)"
  bt_err "Loop reached max iterations ($max_iter) without approval."
  return 1
}
