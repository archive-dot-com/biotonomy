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
const researchFile = String(process.env.BT_STORIES_RESEARCH_FILE || "");

function clean(s) {
  return String(s || "").replace(/\s+/g, " ").trim();
}

function parseResearchRefs(raw) {
  const refs = [];
  const seen = new Set();
  const text = String(raw || "");
  function addRef(candidate) {
    let ref = clean(candidate);
    ref = ref.replace(/^[\x60"]+|[\x60"]+$/g, "");
    ref = ref.replace(/[\x29,.;:]+$/g, "");
    if (!ref) return;
    if (/^https?:\/\//i.test(ref)) return;
    if (!/[\/.]/.test(ref)) return;
    if (seen.has(ref)) return;
    seen.add(ref);
    refs.push(ref);
  }

  const inline = text.match(/\x60[^\x60\n]+\x60/g) || [];
  for (const token of inline) {
    addRef(token.slice(1, -1));
    if (refs.length >= 3) break;
  }
  if (refs.length < 3) {
    const lines = text.split(/\r?\n/);
    let inKeyFiles = false;
    for (const rawLine of lines) {
      const line = rawLine || "";
      if (/^\s*#{1,6}\s*key files to modify\b/i.test(line)) {
        inKeyFiles = true;
        continue;
      }
      if (/^\s*#{1,6}\s+/.test(line) && inKeyFiles) {
        inKeyFiles = false;
      }
      const m = line.match(/^\s*[-*]\s+(.+?)\s*$/);
      if (!m) continue;
      if (!inKeyFiles && !/[\/.]/.test(m[1])) continue;
      const candidate = m[1].split(/\s+(?:--|->|:)\s+/)[0];
      addRef(candidate);
      if (refs.length >= 3) break;
    }
  }
  return refs;
}

const title = clean(j.title);
const body = String(j.body || "").replace(/\r/g, "");
const lines = body.split("\n");
let researchRefs = [];
if (researchFile) {
  try {
    const researchRaw = fs.readFileSync(researchFile, "utf8");
    researchRefs = parseResearchRefs(researchRaw);
  } catch {
    researchRefs = [];
  }
}

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
const maxStories = 5;
const reservedForResearch = researchRefs.length > 0 ? 1 : 0;
const maxBaseStories = Math.max(0, maxStories - reservedForResearch);
if (title && storyTitles.length < maxBaseStories) {
  storyTitles.push(title);
}
for (const bullet of selectedBullets) {
  if (storyTitles.length >= maxBaseStories) {
    break;
  }
  storyTitles.push(bullet);
}
for (const ref of researchRefs) {
  if (storyTitles.length >= maxStories) {
    break;
  }
  storyTitles.push("Apply researched pattern from " + ref);
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
  local research=0
  local arg=""
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      -h|--help)
        cat <<'EOF'
Usage:
  bt spec [--force] [--research] <issue#>
  bt spec [--force] [--research] <feature>

Options:
  --force      Overwrite existing SPEC.md if it already exists.
  --research   Run bt research for the feature before generating stories.

For an <issue#>, requires `gh` and creates `specs/issue-<n>/SPEC.md` using the issue title/body.
For a <feature>, creates `specs/<feature>/SPEC.md` with a minimal, parseable story list.
EOF
        return 0
        ;;
      --force)
        force=1
        shift
        ;;
      --research)
        research=1
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

  local feature issue url_slug
  issue=""
  url_slug=""
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    issue="$arg"
    feature="issue-$arg"
  elif [[ "$arg" =~ ^https?://github.com/([^/]+/[^/]+)/issues/([0-9]+) ]]; then
    # support URL format
    issue="${BASH_REMATCH[2]}"
    url_slug="${BASH_REMATCH[1]}"
    feature="issue-$issue"
  else
    feature="$(bt_require_feature "$arg")"
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

  if (( research == 1 )); then
    if ! bt_codex_available; then
      bt_warn "research skipped: codex unavailable; continuing spec generation without RESEARCH.md"
    else
      # shellcheck source=/dev/null
      source "$BT_ROOT/commands/research.sh"
      local prev_die_mode
      prev_die_mode="${BT_DIE_MODE:-}"
      export BT_DIE_MODE="return"
      if ! bt_cmd_research "$feature"; then
        bt_warn "research step failed for $feature; continuing spec generation"
      fi
      if [[ -n "$prev_die_mode" ]]; then
        export BT_DIE_MODE="$prev_die_mode"
      else
        unset BT_DIE_MODE || true
      fi
    fi
  fi

  if [[ -n "$issue" ]]; then
    bt__require_cmd gh

    local repo
    if [[ -n "$url_slug" ]]; then
      repo="$url_slug"
    else
      repo="$(bt_repo_resolve "$BT_PROJECT_ROOT")"
    fi

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

    local summary stories research_file
    research_file=""
    if (( research == 1 )) && [[ -f "$dir/RESEARCH.md" ]]; then
      research_file="$dir/RESEARCH.md"
    fi
    summary="$(bt__summarize_body "$body")"
    stories="$(BT_STORIES_RESEARCH_FILE="$research_file" bt__stories_from_issue_json <<<"$json")"

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
