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

bt_run_gates() {
  # Runs lint/typecheck/test if configured or auto-detectable. Missing gates are skipped.
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

  local any=0
  if [[ -n "$lint" ]]; then
    any=1
    bt_info "gate: lint ($lint)"
    (cd "$BT_PROJECT_ROOT" && bash -lc "$lint")
  else
    bt_warn "gate: lint skipped (no BT_GATE_LINT and no auto-detect)"
  fi

  if [[ -n "$typecheck" ]]; then
    any=1
    bt_info "gate: typecheck ($typecheck)"
    (cd "$BT_PROJECT_ROOT" && bash -lc "$typecheck")
  else
    bt_warn "gate: typecheck skipped (no BT_GATE_TYPECHECK and no auto-detect)"
  fi

  if [[ -n "$test" ]]; then
    any=1
    bt_info "gate: test ($test)"
    (cd "$BT_PROJECT_ROOT" && bash -lc "$test")
  else
    bt_warn "gate: test skipped (no BT_GATE_TEST and no auto-detect)"
  fi

  [[ "$any" == "1" ]] || bt_warn "no gates ran"
}

