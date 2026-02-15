#!/usr/bin/env bash
set -euo pipefail

bt_notify() {
  local msg="$*"
  [[ -n "${BT_NOTIFY_HOOK:-}" ]] || return 0
  [[ -x "${BT_NOTIFY_HOOK:-}" ]] || {
    bt_warn "BT_NOTIFY_HOOK is set but not executable: $BT_NOTIFY_HOOK"
    return 0
  }
  "$BT_NOTIFY_HOOK" "$msg" || bt_warn "notify hook failed: $BT_NOTIFY_HOOK"
}

