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

bt__loop_strict_review_delta_check() {
  local prev_review="$1"
  local curr_review="$2"

  [[ "${BT_LOOP_STRICT_REVIEW_DELTA:-0}" == "1" ]] || return 0
  [[ -f "$curr_review" ]] || return 0
  [[ -f "$prev_review" ]] || return 0

  local violations
  if violations="$(python3 - <<PY
import re
import sys

prev_path = "$prev_review"
curr_path = "$curr_review"

def extract_findings(path):
    out = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\\r\\n")
            m = re.match(r"^\\s*\\d+\\.\\s+(.*\\S)\\s*$", line)
            if not m:
                continue
            finding = " ".join(m.group(1).split())
            if finding:
                out.append(finding)
    return out

prev_findings = set(extract_findings(prev_path))
violations = []
for finding in extract_findings(curr_path):
    if finding in prev_findings:
        continue
    upper_finding = finding.upper()
    if "[REGRESSION]" in upper_finding or "[SPEC_GAP]" in upper_finding:
        continue
    violations.append(finding)

for finding in violations:
    print(finding)

sys.exit(1 if violations else 0)
PY
)"; then
    return 0
  fi

  bt_err "strict review delta violation: new findings were introduced without [REGRESSION] or [SPEC_GAP]"
  bt_err "previous review: $prev_review"
  bt_err "current review: $curr_review"
  while IFS= read -r finding; do
    [[ -n "$finding" ]] || continue
    bt_err "untagged new finding: $finding"
  done <<<"$violations"
  bt_err "action: tag each new finding with [REGRESSION] or [SPEC_GAP], or tie it directly to fixed rubric/SPEC."
  return 1
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

  feature="$(bt_require_feature "$feature")"

  bt_env_load || true
  bt_ensure_dirs

  local feat_dir
  feat_dir="$(bt_feature_dir "$feature")"
  local spec_file="$feat_dir/SPEC.md"

  if [[ ! -f "$spec_file" ]]; then
    bt_info "SPEC missing; auto-running spec for $feature"
    # shellcheck source=/dev/null
    source "$BT_ROOT/commands/spec.sh"

    local prev_die_mode
    prev_die_mode="${BT_DIE_MODE:-}"
    export BT_DIE_MODE="return"
    local -a spec_args
    spec_args=("$feature")
    if [[ "${BT_SPEC_RESEARCH:-0}" == "1" ]]; then
      spec_args=(--research "$feature")
    fi
    if ! bt_cmd_spec "${spec_args[@]}"; then
      if [[ -n "$prev_die_mode" ]]; then
        export BT_DIE_MODE="$prev_die_mode"
      else
        unset BT_DIE_MODE || true
      fi
      bt_err "auto spec failed for $feature"
      bt_die "loop failed before plan-review due to missing SPEC.md"
    fi
    if [[ -n "$prev_die_mode" ]]; then
      export BT_DIE_MODE="$prev_die_mode"
    else
      unset BT_DIE_MODE || true
    fi
    feat_dir="$(bt_feature_dir "$feature")"
  fi

  # Auto-run plan-review if PLAN_REVIEW.md is missing or unapproved
  local plan_review="$feat_dir/PLAN_REVIEW.md"
  if [[ ! -f "$plan_review" ]] || ! grep -qiE "Verdict:.*(APPROVE_PLAN|APPROVED_PLAN)" "$plan_review"; then
    bt_info "PLAN_REVIEW missing or unapproved; auto-running plan-review..."
    # shellcheck source=/dev/null
    source "$BT_ROOT/commands/plan-review.sh"
    if ! bt_cmd_plan_review "$feature"; then
      bt_err "auto plan-review failed for $feature"
      bt_err "manually run: bt plan-review $feature"
      bt_die "loop hard-fails without approved PLAN_REVIEW verdict before implement/review"
    fi
    # Re-check after auto-run
    if [[ ! -f "$plan_review" ]] || ! grep -qiE "Verdict:.*(APPROVE_PLAN|APPROVED_PLAN)" "$plan_review"; then
      bt_err "plan-review ran but did not produce an approved verdict"
      bt_err "check $plan_review and re-run: bt plan-review $feature"
      bt_die "loop hard-fails without approved PLAN_REVIEW verdict before implement/review"
    fi
    bt_info "plan-review auto-approved; continuing loop"
  fi

  bt_info "starting loop for: $feature (max iterations: $max_iter)"

  bt_info "running preflight gates..."
  if [[ "${BT_LOOP_REQUIRE_GATES:-0}" == "1" ]]; then
    if ! bt_run_gates --require-any; then
      bt_err "preflight gates failed (or none configured); aborting before implement/review"
      return 1
    fi
  else
    if ! bt_run_gates; then
      bt_err "preflight gates failed (or none configured); aborting before implement/review"
      return 1
    fi
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
  local resume_iter=0
  local should_resume=0

  mkdir -p "$history_dir"
  if [[ -f "$progress_file" ]]; then
    local resume_meta
    resume_meta="$(python3 - <<PY
import json
p = "$progress_file"
max_iter = $max_iter
try:
    with open(p, "r", encoding="utf-8") as f:
        d = json.load(f)
except Exception:
    print("0 0")
    raise SystemExit(0)
result = str(d.get("result", ""))
completed = d.get("completedIterations", 0)
try:
    completed = int(completed)
except Exception:
    completed = 0
if result in {"in-progress", "implement-failed"} and completed < max_iter:
    d["feature"] = "$feature"
    d["maxIterations"] = max_iter
    d["completedIterations"] = completed
    d["result"] = "in-progress"
    if not isinstance(d.get("iterations"), list):
        d["iterations"] = []
    with open(p, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2)
    print(f"1 {completed}")
else:
    print("0 0")
PY
)"
    if [[ "$resume_meta" =~ ^1[[:space:]]+([0-9]+)$ ]]; then
      should_resume=1
      resume_iter="${BASH_REMATCH[1]}"
    fi
  fi

  if [[ "$should_resume" == "1" ]]; then
    iter="$resume_iter"
    bt_info "resuming loop from iteration $((iter + 1)) / $max_iter"
  else
    cat > "$progress_file" <<EOF
{
  "feature": "$feature",
  "maxIterations": $max_iter,
  "completedIterations": 0,
  "result": "in-progress",
  "iterations": []
}
EOF
  fi

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

    local prev_review_file=""
    if [[ "$iter" -gt 1 ]]; then
      local prev_iter_padded
      prev_iter_padded="$(printf "%03d" "$((iter - 1))")"
      local candidate
      for candidate in "$history_dir"/*"-loop-iter-$prev_iter_padded.md"; do
        [[ -f "$candidate" ]] || continue
        prev_review_file="$candidate"
        break
      done
    fi
    if [[ -n "$prev_review_file" ]]; then
      if ! bt__loop_strict_review_delta_check "$prev_review_file" "$review_file"; then
        return 1
      fi
    fi

    local verdict
    verdict="$(awk '/^Verdict:/{print toupper($2); exit}' "$review_file" | tr -d '\r' || true)"
    bt_info "verdict: $verdict"

    # 4. Final Gate Check for convergence
    # We use the gates result from the last command that ran them (implement/fix).
    # bt_cmd_implement/fix return non-zero if gates fail, but we capture the status.
    # We call bt_run_gates here just to be sure of the final state post-review.
    local gates_ok=1
    if ! bt_run_gates --require-any; then
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
