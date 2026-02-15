#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$BT_ROOT/lib/state.sh"

bt__require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || bt_die "missing required command: $cmd"
}

bt__summarize_body() {
  local s="${1:-}"
  s="${s//$'\r'/}"
  # Collapse whitespace and cap length so the SPEC stays readable.
  s="$(printf '%s' "$s" | sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ *//; s/ *$//')"
  if (( ${#s} > 900 )); then
    s="${s:0:897}..."
  fi
  printf '%s\n' "$s"
}

bt__json_fields_sep() {
  # Reads JSON on stdin and prints: title<US>url<US>body (US = 0x1f).
  # Avoid NUL: bash variables can't reliably hold it.
  bt__require_cmd node
  node -e "$(
    cat <<'NODE'
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
const title = (j.title ?? "").toString();
const url = (j.url ?? "").toString();
// Make body newline-free so bash `read` (used by the caller) does not truncate it.
const body = (j.body ?? "").toString().replace(/[\r\n]+/g, " ");
// Ensure a terminating newline so bash `read` does not exit non-zero at EOF.
process.stdout.write(title + "\x1f" + url + "\x1f" + body + "\n");
NODE
  )"
}

bt_cmd_spec() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  bt spec <issue#>
  bt spec <feature>

For an <issue#>, requires `gh` and creates `specs/issue-<n>/SPEC.md` using the issue title/body.
For a <feature>, creates `specs/<feature>/SPEC.md` with a minimal, parseable story list.
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

  if [[ -n "$issue" ]]; then
    bt__require_cmd gh

    local repo
    repo="$(bt_repo_resolve "$BT_PROJECT_ROOT")"

    local -a gh_cmd
    gh_cmd=(gh issue view "$issue" -R "$repo" --json "title,body,url")

    local json
    local errf
    errf="$(mktemp "${TMPDIR:-/tmp}/bt-gh-err.XXXXXX")"
    if ! json="$("${gh_cmd[@]}" 2>"$errf")"; then
      local ec=$?
      local err
      err="$(cat "$errf" 2>/dev/null || true)"
      rm -f "$errf" || true
      bt_die "failed to fetch issue #$issue via gh (exit $ec): $err"
    fi
    rm -f "$errf" || true

    local title url body
    IFS=$'\x1f' read -r title url body < <(printf '%s' "$json" | bt__json_fields_sep)
    [[ -n "$title" ]] || title="(untitled)"
    [[ -n "$url" ]] || url="https://github.com/$repo/issues/$issue"

    local summary
    summary="$(bt__summarize_body "$body")"

    cat >"$spec" <<EOF
---
name: $feature
branch: feat/$feature
issue: $issue
repo: $repo
---

# Problem

## $title

- **issue:** #$issue
- **link:** $url

$summary

# Stories

## [ID:S1] Confirm repo resolution and env fallback
- **status:** draft
- **priority:** 1
- **acceptance:** bt can determine repo slug from git remote origin; otherwise requires BT_REPO
- **tests:**

## [ID:S2] Fetch issue details via gh
- **status:** draft
- **priority:** 1
- **acceptance:** bt spec <issue#> uses gh to retrieve title/body/url and handles errors clearly
- **tests:**

## [ID:S3] Generate a SPEC.md with frontmatter + problem summary
- **status:** draft
- **priority:** 1
- **acceptance:** SPEC includes required frontmatter, a Problem section, and a Stories section (3-7 stories)
- **tests:**

## [ID:S4] Record exact gh commands used in SPEC footer
- **status:** draft
- **priority:** 2
- **acceptance:** SPEC footer includes the exact gh command(s) executed
- **tests:**

## [ID:S5] Add tests stubbing gh via PATH
- **status:** draft
- **priority:** 1
- **acceptance:** tests run offline and validate SPEC content generation
- **tests:**

---

## Footer

### gh
- \`${gh_cmd[*]}\`
EOF

    bt_progress_append "$feature" "spec created (from gh issue $repo#$issue)"
    bt_history_write "$feature" "spec" "Created SPEC.md from $repo#$issue."
    bt_info "wrote $spec"
    bt_notify "bt spec created for $feature"
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
