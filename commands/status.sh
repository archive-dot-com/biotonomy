#!/usr/bin/env bash
set -euo pipefail

bt__count_statuses() {
  local spec="$1"
  awk '
    BEGIN { pending=0; in_progress=0; done=0; failed=0; blocked=0; total=0 }
    /^[[:space:]]*- \*\*status:\*\*/ {
      s=$0
      sub(/^[[:space:]]*- \*\*status:\*\*[[:space:]]*/,"",s)
      gsub(/[[:space:]]+/,"",s)
      total++
      if (s=="pending") pending++
      else if (s=="in_progress") in_progress++
      else if (s=="done" || s=="completed") done++
      else if (s=="failed") failed++
      else if (s=="blocked") blocked++
    }
    END {
      printf("stories=%d pending=%d in_progress=%d done=%d failed=%d blocked=%d\n",
        total,pending,in_progress,done,failed,blocked)
    }
  ' "$spec" 2>/dev/null || true
}

# New bt__show_gates for the new JSON format:
# {"ts": "2026-02-15T17:38:00Z", "results": {"lint": {"cmd": "...", "status": 0}, ...}}
bt__show_gates() {
  local json_file="$1"
  [[ -f "$json_file" ]] || return 0
  
  local json
  json="$(cat "$json_file")"
  
  local ts
  ts=$(printf '%s' "$json" | grep -oE '"ts"[[:space:]]*:[[:space:]]*"[^"]+"' | cut -d'"' -f4 || echo "unknown")
  
  # A simple heuristic to check if any status is non-zero
  # We look for "status": N where N > 0 (whitespace-insensitive)
  local fails
  fails=$(printf '%s' "$json" | grep -oE '"status"[[:space:]]*:[[:space:]]*[1-9][0-9]*' | wc -l | xargs)
  
  local status="pass"
  [[ "$fails" -gt 0 ]] && status="fail"

  # Also list which ones failed if any
  local detail=""
  if [[ "$fails" -gt 0 ]]; then
    # Extremely primitive extraction of keys with non-zero status
    # Assumes format "key": {"cmd": "...", "status": N}
    detail=" ("
    local k
    # This regex is a bit fragile but works for the predictable format we write
    for k in "lint" "typecheck" "test"; do
        if echo "$json" | grep -qE "\"$k\"[[:space:]]*:[[:space:]]*\{[^\}]*\"status\"[[:space:]]*:[[:space:]]*[1-9][0-9]*"; then
            detail="${detail}${k} "
        fi
    done
    detail="${detail% })"
  fi
  
  printf " [gates:%s %s%s]" "$status" "$ts" "$detail"
}

bt_cmd_status() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt status

Shows basic Biotonomy configuration and SPEC.md progress summary.
EOF
    return 0
  fi

  bt_env_load || true

  echo "bt v0.1.0"
  echo "project_root: $BT_PROJECT_ROOT"
  echo "env_file: ${BT_ENV_FILE:-<none>}"
  echo "specs_dir: $BT_SPECS_DIR"
  echo "state_dir: $BT_STATE_DIR"
  echo "notify_hook: ${BT_NOTIFY_HOOK:-<none>}"

  local state_dir="$BT_PROJECT_ROOT/$BT_STATE_DIR/state"
  [[ -f "$state_dir/gates.json" ]] && echo "global:$(bt__show_gates "$state_dir/gates.json")"

  local specs_path="$BT_PROJECT_ROOT/$BT_SPECS_DIR"
  if [[ ! -d "$specs_path" ]]; then
    echo "specs: <missing> ($specs_path)"
    return 0
  fi

  local any=0
  local d
  for d in "$specs_path"/*; do
    [[ -d "$d" ]] || continue
    any=1
    local feat
    feat="$(basename "$d")"
    local spec="$d/SPEC.md"
    local summary
    if [[ -f "$spec" ]]; then
      summary="$(bt__count_statuses "$spec")"
    else
      summary="SPEC.md=<missing>"
    fi
    local gates_sum
    gates_sum="$(bt__show_gates "$d/gates.json")"
    echo "feature: $feat $summary$gates_sum"
  done

  [[ "$any" == "1" ]] || echo "features: <none>"
}
