#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
biotonomy (bt) v0.1.0

Usage:
  bt <command> [args]

Commands:
  bootstrap  spec  research  implement  review  fix  compound  design  status  reset

Run:
  bt <command> --help
EOF
}

cmd="${1:-help}"
case "$cmd" in
  -h|--help|help) usage ;;
  *)
    echo "bt: command '$cmd' not implemented yet" >&2
    usage >&2
    exit 2
    ;;
esac

