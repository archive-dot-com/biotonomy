#!/usr/bin/env bash
set -euo pipefail

# Minimal Telegram notification hook.
#
# Required env:
#   TELEGRAM_BOT_TOKEN
#   TELEGRAM_CHAT_ID
#
# Usage:
#   BT_NOTIFY_HOOK=./hooks/telegram.sh bt status

msg="$*"
[[ -n "${msg:-}" ]] || exit 0

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "telegram hook: missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID" >&2
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "telegram hook: curl not found" >&2
  exit 0
fi

curl -fsS \
  -X POST \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${msg}" \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" >/dev/null

