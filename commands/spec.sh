#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt_cmd_spec() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt spec <issue#>
  bt spec <feature>

Creates `specs/<feature>/SPEC.md` with a minimal, parseable story list.
EOF
    return 0
  fi

  bt_env_load || true
  bt_ensure_dirs

  local arg="${1:-}"
  [[ -n "$arg" ]] || bt_die "spec requires <issue#> or <feature>"

  local feature issue
  issue=""
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    issue="$arg"
    feature="issue-$arg"
  else
    feature="$arg"
  fi

  local dir
  dir="$(bt_feature_dir "$feature")"
  mkdir -p "$dir/history"

  local spec="$dir/SPEC.md"
  if [[ -f "$spec" ]]; then
    bt_info "SPEC already exists: $spec"
    return 0
  fi

  cat >"$spec" <<EOF
---
name: $feature
branch: feat/$feature
issue: ${issue:-}
repo:
---

# Stories

## [ID:S1] Define acceptance criteria
- **status:** pending
- **priority:** 1
- **acceptance:** SPEC.md is filled out with real stories and tests
- **tests:**

EOF

  bt_progress_append "$feature" "spec created"
  bt_history_write "$feature" "spec" "Created SPEC.md for $feature."
  bt_info "wrote $spec"
  bt_notify "bt spec created for $feature"
}

