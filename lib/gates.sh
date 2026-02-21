#!/usr/bin/env bash
set -euo pipefail

bt__gate_detect() {
  # Output: lint|typecheck|test command strings (one per line) for the detected ecosystem.
  # Empty output => no auto-detection.
  if [[ -f "$BT_PROJECT_ROOT/pnpm-lock.yaml" ]]; then
    printf '%s\n' "lint=pnpm lint" "typecheck=pnpm typecheck" "test=pnpm test"
    return 0
  fi
  if [[ -f "$BT_PROJECT_ROOT/yarn.lock" ]]; then
    printf '%s\n' "lint=yarn lint" "typecheck=yarn typecheck" "test=yarn test"
    return 0
  fi
  if [[ -f "$BT_PROJECT_ROOT/package-lock.json" ]]; then
    printf '%s\n' "lint=npm run lint" "typecheck=npm run typecheck" "test=npm test"
    return 0
  fi
  if [[ -f "$BT_PROJECT_ROOT/Makefile" ]]; then
    printf '%s\n' "lint=make lint" "typecheck=make typecheck" "test=make test"
    return 0
  fi
  return 1
}

bt__gate_cmd() {
  local gate="$1"
  case "$gate" in
    lint) printf '%s\n' "${BT_GATE_LINT:-}" ;;
    typecheck) printf '%s\n' "${BT_GATE_TYPECHECK:-}" ;;
    test) printf '%s\n' "${BT_GATE_TEST:-}" ;;
    *) return 1 ;;
  esac
}

bt__json_escape() {
  local s="${1-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\b'/\\b}"
  s="${s//$'\f'/\\f}"
  printf '%s' "$s"
}

# Returns gate config (key=cmd) for those available.
bt_get_gate_config() {
  local detected
  detected="$(bt__gate_detect 2>/dev/null || true)"

  local lint typecheck test
  lint="$(bt__gate_cmd lint)"
  typecheck="$(bt__gate_cmd typecheck)"
  test="$(bt__gate_cmd test)"

  if [[ -z "$lint" || -z "$typecheck" || -z "$test" ]]; then
    local line k v
    while IFS= read -r line; do
      [[ "$line" == *"="* ]] || continue
      k="${line%%=*}"
      v="${line#*=}"
      case "$k" in
        lint) [[ -n "$lint" ]] || lint="$v" ;;
        typecheck) [[ -n "$typecheck" ]] || typecheck="$v" ;;
        test) [[ -n "$test" ]] || test="$v" ;;
      esac
    done <<<"$detected"
  fi

  [[ -n "$lint" ]] && printf 'lint=%s\n' "$lint"
  [[ -n "$typecheck" ]] && printf 'typecheck=%s\n' "$typecheck"
  [[ -n "$test" ]] && printf 'test=%s\n' "$test"
}

# Runs gates and returns a JSON string fragment with results.
# Writes logs to stderr. Returns 0 if all gates passed, 1 otherwise.
bt__gate_script_exists() {
  # Check if an npm/pnpm/yarn script actually exists in package.json.
  # Returns 0 if the script exists or if we can't determine (non-npm project).
  local cmd="$1"
  local script_name=""

  # Extract script name from common patterns
  case "$cmd" in
    "npm run "*)  script_name="${cmd#npm run }" ;;
    "npm test")   script_name="test" ;;
    "pnpm "*)     script_name="${cmd#pnpm }" ;;
    "yarn "*)     script_name="${cmd#yarn }" ;;
    *)            return 0 ;;  # Not an npm-style command, assume exists
  esac
  script_name="${script_name%% *}"  # Take first word only

  local pkg="$BT_PROJECT_ROOT/package.json"
  [[ -f "$pkg" ]] || return 0  # No package.json, can't check

  # Check if script exists in package.json
  if command -v node >/dev/null 2>&1; then
    node -e "const p=require('$pkg'); process.exit(p.scripts && p.scripts['$script_name'] ? 0 : 1)" 2>/dev/null
    return $?
  fi
  return 0  # Can't verify, assume exists
}

bt__gate_run_cmd() {
  local cmd="$1"
  (
    cd "$BT_PROJECT_ROOT" || exit 1
    # Keep user env, but avoid leaking bt root/target plumbing into child test processes.
    env -u BT_PROJECT_ROOT -u BT_ENV_FILE -u BT_TARGET_DIR bash -lc "$cmd"
  )
}

bt_run_gates() {
  local require_any=0
  if [[ "${1:-}" == "--require-any" ]]; then
    require_any=1
    shift
  fi

  local config
  config="$(bt_get_gate_config)"

  local line k v
  local results_json=""
  local overall_ok=0
  local any=0

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    k="${line%%=*}"
    v="${line#*=}"

    # Skip gates explicitly set to "skip" or "" (disabled)
    if [[ "$v" == "skip" || -z "$v" ]]; then
      bt_warn "gate disabled: $k"
      local entry k_json v_json
      k_json="$(bt__json_escape "$k")"
      v_json="$(bt__json_escape "$v")"
      printf -v entry '"%s": {"cmd": "%s", "status": -1, "skipped": true}' "$k_json" "$v_json"
      if [[ -z "$results_json" ]]; then results_json="$entry"; else results_json="$results_json, $entry"; fi
      continue
    fi

    # Skip gates whose scripts don't exist
    if ! bt__gate_script_exists "$v"; then
      bt_warn "gate skipped (script missing): $k ($v)"
      local entry k_json v_json
      k_json="$(bt__json_escape "$k")"
      v_json="$(bt__json_escape "$v")"
      printf -v entry '"%s": {"cmd": "%s", "status": -1, "skipped": true}' "$k_json" "$v_json"
      if [[ -z "$results_json" ]]; then results_json="$entry"; else results_json="$results_json, $entry"; fi
      continue
    fi

    any=1

    bt_info "gate: $k ($v)"
    local status=0
    if ! bt__gate_run_cmd "$v"; then
      bt_err "gate failed: $k"
      status=1
      overall_ok=1
    fi

    local entry k_json v_json
    k_json="$(bt__json_escape "$k")"
    v_json="$(bt__json_escape "$v")"
    printf -v entry '"%s": {"cmd": "%s", "status": %d}' "$k_json" "$v_json" "$status"
    if [[ -z "$results_json" ]]; then
      results_json="$entry"
    else
      results_json="$results_json, $entry"
    fi
  done <<<"$config"

  if [[ "$any" == "0" ]]; then
    bt_warn "no gates ran"
    printf '{"ts": "%s", "results": {}}\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    if [[ "$require_any" == "1" ]]; then
      return 1
    fi
    return 0
  fi

  printf '{"ts": "%s", "results": {%s}}\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$results_json"
  return "$overall_ok"
}
