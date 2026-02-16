#!/usr/bin/env bash
set -euo pipefail

bt_is_valid_repo_slug() {
  local slug="${1:-}"
  # Keep this strict and predictable: owner/repo with common GitHub-safe chars.
  [[ -n "$slug" ]] || return 1
  [[ "$slug" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || return 1
  return 0
}

bt_parse_repo_from_remote_url() {
  local url="${1:-}"
  [[ -n "$url" ]] || return 1

  local slug=""
  case "$url" in
    git@github.com:*)
      slug="${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      slug="${url#ssh://git@github.com/}"
      ;;
    https://github.com/*)
      slug="${url#https://github.com/}"
      ;;
    http://github.com/*)
      slug="${url#http://github.com/}"
      ;;
    *)
      return 1
      ;;
  esac

  slug="${slug%.git}"
  bt_is_valid_repo_slug "$slug" || return 1
  printf '%s\n' "$slug"
}

bt_repo_from_git_origin() {
  # Best-effort: only rely on origin if we're in a git worktree and origin is set.
  local root="${1:-$PWD}"
  command -v git >/dev/null 2>&1 || return 1

  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local url
  url="$(git -C "$root" config --get remote.origin.url 2>/dev/null || true)"
  [[ -n "$url" ]] || return 1
  bt_parse_repo_from_remote_url "$url"
}

bt_repo_resolve() {
  local root="${1:-${BT_PROJECT_ROOT:-$PWD}}"

  local slug=""
  slug="$(bt_repo_from_git_origin "$root" 2>/dev/null || true)"
  if [[ -n "$slug" ]]; then
    printf '%s\n' "$slug"
    return 0
  fi

  if [[ -n "${BT_REPO:-}" ]]; then
    bt_is_valid_repo_slug "$BT_REPO" || bt_die "invalid BT_REPO (expected owner/repo): $BT_REPO"
    printf '%s\n' "$BT_REPO"
    return 0
  fi

  bt_die "repo resolution failed: set BT_REPO=owner/repo in .bt.env (no usable git remote origin found)"
}

