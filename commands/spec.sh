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

bt__stories_from_issue_json() {
  bt__require_cmd node
  node -e "$(
    cat <<'NODE'
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(0, "utf8") || "{}");

function clean(s) {
  return String(s || "").replace(/\s+/g, " ").trim();
}

const title = clean(j.title);
const body = String(j.body || "").replace(/\r/g, "");
const lines = body.split("\n");

let inAcceptance = false;
const acceptanceBullets = [];
const allBullets = [];
for (const rawLine of lines) {
  const line = rawLine || "";
  if (/^\s*#{1,6}\s*acceptance\b/i.test(line) || /^\s*acceptance criteria\s*:?\s*$/i.test(line)) {
    inAcceptance = true;
    continue;
  }
  if (/^\s*#{1,6}\s+/.test(line) && inAcceptance) {
    inAcceptance = false;
  }

  const m = line.match(/^\s*[-*]\s+(?:\[[ xX]\]\s*)?(.+?)\s*$/);
  if (!m) {
    continue;
  }
  const bullet = clean(m[1]);
  if (!bullet) {
    continue;
  }
  allBullets.push(bullet);
  if (inAcceptance) {
    acceptanceBullets.push(bullet);
  }
}

const selectedBullets = acceptanceBullets.length > 0 ? acceptanceBullets : allBullets;
const storyTitles = [];
if (title) {
  storyTitles.push(title);
}
for (const bullet of selectedBullets) {
  if (storyTitles.length >= 5) {
    break;
  }
  storyTitles.push(bullet);
}

if (storyTitles.length === 0) {
  const fallback = clean(body).slice(0, 120);
  if (fallback) {
    storyTitles.push(fallback);
  } else {
    storyTitles.push("Capture issue requirements");
  }
}

let out = "";
for (let i = 0; i < storyTitles.length; i += 1) {
  const id = i + 1;
  const titleText = storyTitles[i];
  out += "## [ID:S" + id + "] " + titleText + "\n";
  out += "- **status:** draft\n";
  out += "- **priority:** " + (id <= 3 ? 1 : 2) + "\n";
  out += "- **acceptance:** " + titleText + "\n";
  out += "- **tests:**\n\n";
}
process.stdout.write(out);
NODE
  )"
}

bt_cmd_spec() {
  local force=0
  local arg=""
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      -h|--help)
        cat <<'EOF'
Usage:
  bt spec [--force] <issue#>
  bt spec [--force] <feature>

Options:
  --force   Overwrite existing SPEC.md if it already exists.

For an <issue#>, requires `gh` and creates `specs/issue-<n>/SPEC.md` using the issue title/body.
For a <feature>, creates `specs/<feature>/SPEC.md` with a minimal, parseable story list.
EOF
        return 0
        ;;
      --force)
        force=1
        shift
        ;;
      --*)
        bt_die "unknown option for spec: $1"
        ;;
      *)
        if [[ -n "$arg" ]]; then
          bt_die "spec accepts exactly one <issue#> or <feature>"
        fi
        arg="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$arg" ]]; then
    bt_die "spec requires <issue#> or <feature>"
  fi

  bt_env_load || true
  bt_ensure_dirs

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
    if (( force == 1 )); then
      bt_info "overwriting existing SPEC: $spec"
    else
      bt_info "SPEC already exists: $spec"
      return 0
    fi
  fi

  if [[ -n "$issue" ]]; then
    bt__require_cmd gh

    local repo
    repo="$(bt_repo_resolve "$BT_PROJECT_ROOT")"

    local -a gh_cmd
    gh_cmd=(gh issue view "$issue" -R "$repo" --json "title,body,url")

    local json errf artifacts_dir
    artifacts_dir="$dir/.artifacts"
    mkdir -p "$artifacts_dir"
    # Deterministic stderr capture for reproducible runs (avoid mktemp randomness).
    errf="$artifacts_dir/gh.stderr"
    : >"$errf"
    if ! json="$("${gh_cmd[@]}" 2>"$errf")"; then
      local ec=$?
      local err
      err="$(cat "$errf" 2>/dev/null || true)"
      bt_die "failed to fetch issue #$issue via gh (exit $ec): $err"
    fi
    rm -f "$errf" || true

    local title url body
    IFS=$'\x1f' read -r title url body < <(printf '%s' "$json" | bt__json_fields_sep)
    [[ -n "$title" ]] || title="(untitled)"
    [[ -n "$url" ]] || url="https://github.com/$repo/issues/$issue"

    local summary stories
    summary="$(bt__summarize_body "$body")"
    stories="$(printf '%s' "$json" | bt__stories_from_issue_json)"

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

${stories}

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
