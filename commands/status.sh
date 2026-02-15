#!/usr/bin/env bash
set -euo pipefail

bt__count_statuses() {
  local spec="$1"
  awk '
    BEGIN { pending=0; in_progress=0; done=0; failed=0; blocked=0; total=0 }
    /^\- \*\*status:\*\*/ {
      s=$0
      sub(/.*\*\*status:\*\* /,"",s)
      gsub(/[[:space:]]+/,"",s)
      total++
      if (s=="pending") pending++
      else if (s=="in_progress") in_progress++
      else if (s=="done") done++
      else if (s=="failed") failed++
      else if (s=="blocked") blocked++
    }
    END {
      printf("stories=%d pending=%d in_progress=%d done=%d failed=%d blocked=%d\n",
        total,pending,in_progress,done,failed,blocked)
    }
  ' "$spec" 2>/dev/null || true
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
    local spec="$d/SPEC.md"
    if [[ -f "$spec" ]]; then
      echo "feature: $(basename "$d") $([ -f "$spec" ] && bt__count_statuses "$spec")"
    else
      echo "feature: $(basename "$d") SPEC.md=<missing>"
    fi
  done

  [[ "$any" == "1" ]] || echo "features: <none>"
}

