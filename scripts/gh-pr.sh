#!/usr/bin/env bash
set -euo pipefail

# Safe, opt-in PR helper using gh.
# Defaults to dry-run (prints commands). Pass --run to execute.

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  npm run pr:open -- <feature> [--run] [--dry-run] [--base <branch>] [--remote <name>] [--draft]

Notes:
  - Default mode is --dry-run (no git/gh side effects).
  - Determines branch from specs/<feature>/SPEC.md frontmatter (branch: ...), else uses feat/<feature>.
EOF
}

run_mode="dry-run"
base=""
remote="origin"
draft=0
feature=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --run) run_mode="run"; shift ;;
    --dry-run) run_mode="dry-run"; shift ;;
    --base) base="${2:-}"; shift 2 ;;
    --remote) remote="${2:-}"; shift 2 ;;
    --draft) draft=1; shift ;;
    -*)
      echo "pr: unknown flag: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      feature="$1"
      shift
      ;;
  esac
done

[[ -n "$feature" ]] || { usage >&2; exit 2; }

run_cmd() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  if [[ "$run_mode" == "run" ]]; then
    "$@"
  fi
}

if ! command -v git >/dev/null 2>&1; then
  echo "pr: git not found" >&2
  exit 127
fi

if [[ "$run_mode" == "run" ]] && ! command -v gh >/dev/null 2>&1; then
  echo "pr: gh not found (install GitHub CLI or re-run with --dry-run)" >&2
  exit 127
fi

specs_dir="${BT_SPECS_DIR:-specs}"
spec="$specs_dir/$feature/SPEC.md"

branch="feat/$feature"
repo=""
issue=""

if [[ -f "$spec" ]]; then
  # Read simple YAML-ish frontmatter keys (one per line).
  b="$(awk -F': *' '$1=="branch"{print $2; exit}' "$spec" | tr -d '\r')"
  r="$(awk -F': *' '$1=="repo"{print $2; exit}' "$spec" | tr -d '\r')"
  i="$(awk -F': *' '$1=="issue"{print $2; exit}' "$spec" | tr -d '\r')"
  [[ -n "${b:-}" ]] && branch="$b"
  [[ -n "${r:-}" ]] && repo="$r"
  [[ -n "${i:-}" ]] && issue="$i"
fi

if [[ -z "$base" ]]; then
  # Try to detect the default remote HEAD (origin/main vs origin/master, etc.).
  ref="$(git symbolic-ref -q "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
  if [[ -n "$ref" ]]; then
    base="${ref##*/}"
  else
    base="main"
  fi
fi

title="feat: $feature"
body="Feature: $feature"
if [[ -n "$repo" && -n "$issue" ]]; then
  body="$body
Issue: https://github.com/$repo/issues/$issue"
fi
if [[ -f "$spec" ]]; then
  body="$body
Spec: $spec"
fi

if git show-ref --verify --quiet "refs/heads/$branch"; then
  run_cmd git checkout "$branch"
else
  run_cmd git checkout -b "$branch"
fi

run_cmd git push -u "$remote" "$branch"

pr_args=(pr create --head "$branch" --base "$base" --title "$title" --body "$body")
if [[ "$draft" == "1" ]]; then
  pr_args+=(--draft)
fi
run_cmd gh "${pr_args[@]}"

