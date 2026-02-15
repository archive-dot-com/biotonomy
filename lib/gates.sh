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
bt_run_gates() {
  local config
  config="$(bt_get_gate_config)"

  local line k v
  local results_json=""
  local overall_ok=0
  local any=0

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    any=1
    k="${line%%=*}"
    v="${line#*=}"

    bt_info "gate: $k ($v)"
    local status=0
    # Use bash -lc for interactivity if needed, but we typically want it non-interactive.
    # The original used bash -lc "$v". We'll stick to that but capture status.
    if ! (cd "$BT_PROJECT_ROOT" && bash -lc "$v"); then
      bt_err "gate failed: $k"
      status=1
      overall_ok=1
    fi

    local entry
    printf -v entry '"%s": {"cmd": "%s", "status": %d}' "$k" "$v" "$status"
    if [[ -z "$results_json" ]]; then
      results_json="$entry"
    else
      results_json="$results_json, $entry"
    fi
  done <<<"$config"

  if [[ "$any" == "0" ]]; then
    bt_warn "no gates ran"
    printf '{"ts": "%s", "results": {}}\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    return 0
  fi

  printf '{"ts": "%s", "results": {%s}}\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$results_json"
  return "$overall_ok"
}
