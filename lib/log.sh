#!/usr/bin/env bash
set -euo pipefail

bt__is_tty() { [[ -t 2 ]]; }

bt__color() {
  local code="$1"
  if [[ "${BT_NO_COLOR:-0}" == "1" ]] || ! bt__is_tty; then
    printf ''
  else
    printf '\033[%sm' "$code"
  fi
}

bt__reset() {
  if [[ "${BT_NO_COLOR:-0}" == "1" ]] || ! bt__is_tty; then
    printf ''
  else
    printf '\033[0m'
  fi
}

bt__ts() {
  date +"%Y-%m-%d %H:%M:%S"
}

bt_info() {
  printf '%s %sinfo%s %s\n' "$(bt__ts)" "$(bt__color 32)" "$(bt__reset)" "$*" >&2
}

bt_warn() {
  printf '%s %swarn%s %s\n' "$(bt__ts)" "$(bt__color 33)" "$(bt__reset)" "$*" >&2
}

bt_err() {
  printf '%s %serr%s  %s\n' "$(bt__ts)" "$(bt__color 31)" "$(bt__reset)" "$*" >&2
}

bt_debug() {
  [[ "${BT_DEBUG:-0}" == "1" ]] || return 0
  printf '%s %sdbg%s  %s\n' "$(bt__ts)" "$(bt__color 90)" "$(bt__reset)" "$*" >&2
}

bt_die() {
  bt_err "$*"
  exit 1
}

