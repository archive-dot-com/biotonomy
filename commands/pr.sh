#!/usr/bin/env bash
# biotonomy pr command

bt_pr_usage() {
  cat <<EOF
Usage: bt pr <feature-name> [options]

Ship a feature by running tests, committing changes, pushing, and creating a PR.

Options:
  --run         Actually execute push and gh pr create (default: dry-run)
  --dry-run     Print push and gh commands without executing
  --draft       Create the PR as a draft
  --base <ref>  Base branch for the PR (default: remote's HEAD or main)
  --remote <n>  Remote to push to (default: origin)
  --no-commit   Skip committing changes (expects they are already committed)
  -h, --help    Show this help
EOF
}

bt_pr_file_size_bytes() {
  local f="$1"
  local sz=""
  # macOS/BSD stat
  if sz="$(stat -f%z "$f" 2>/dev/null)"; then
    printf '%s\n' "$sz"
    return 0
  fi
  # GNU stat
  if sz="$(stat -c%s "$f" 2>/dev/null)"; then
    printf '%s\n' "$sz"
    return 0
  fi
  # Fallback
  wc -c <"$f" | tr -d ' '
}

bt_pr_is_text_file() {
  local f="$1"
  # grep -I treats binary as non-matching and exits 1; empty files also exit 1, so handle empties elsewhere.
  LC_ALL=C grep -Iq . "$f" 2>/dev/null
}

bt_pr_append_artifact_section() {
  local out_file="$1"
  local relpath="$2"
  local abspath="$3"
  local max_inline_bytes="$4"

  {
    # shellcheck disable=SC2016
    printf '\n### `%s`\n' "$relpath"
    # shellcheck disable=SC2016
    printf 'Path: [`%s`](%s)\n\n' "$relpath" "$relpath"

    if [[ ! -f "$abspath" ]]; then
      printf "_missing_\\n"
      return 0
    fi

    local size
    size="$(bt_pr_file_size_bytes "$abspath")"

    if [[ "$size" -ge "$max_inline_bytes" ]]; then
      printf "_not inlined (size: %s bytes)_\\n" "$size"
      return 0
    fi

    if [[ "$size" -gt 0 ]] && ! bt_pr_is_text_file "$abspath"; then
      printf "_not inlined (binary or non-text; size: %s bytes)_\\n" "$size"
      return 0
    fi

    local fence='```'
    if grep -q '```' "$abspath" 2>/dev/null; then
      fence='````'
    fi

    printf "%s\\n" "$fence"
    cat "$abspath"
    # Ensure trailing newline so the closing fence is on its own line.
    printf "\\n%s\\n" "$fence"
  } >>"$out_file"
}

bt_pr_write_artifacts_comment() {
  local feature="$1"
  local specs_dir="$2"
  local out_file="$3"

  local max_inline_bytes=$((20 * 1024))
  local spec_rel="$specs_dir/$feature/SPEC.md"
  local review_rel="$specs_dir/$feature/REVIEW.md"
  local artifacts_dir_rel="$specs_dir/$feature/.artifacts"

  : >"$out_file"
  {
    printf "## Artifacts\\n\\n"
    # shellcheck disable=SC2016
    printf 'Feature: `%s`\n' "$feature"
  } >>"$out_file"

  bt_pr_append_artifact_section "$out_file" "$spec_rel" "$spec_rel" "$max_inline_bytes"

  if [[ -f "$review_rel" ]]; then
    bt_pr_append_artifact_section "$out_file" "$review_rel" "$review_rel" "$max_inline_bytes"
  fi

  if [[ -d "$artifacts_dir_rel" ]]; then
    local f
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      bt_pr_append_artifact_section "$out_file" "$f" "$f" "$max_inline_bytes"
    done < <(find "$artifacts_dir_rel" -type f -print | LC_ALL=C sort)
  fi
}

bt_cmd_pr() {
  local feature=""
  local run_mode="dry-run"
  local draft=0
  local base=""
  local remote="origin"
  local commit=1

  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      -h|--help) bt_pr_usage; return 0 ;;
      --run) run_mode="run"; shift ;;
      --dry-run) run_mode="dry-run"; shift ;;
      --draft) draft=1; shift ;;
      --base)
        if [[ $# -lt 2 || "${2:-}" == -* ]]; then
          bt_err "--base requires a value"
          return 2
        fi
        base="${2:-}"
        shift 2
        ;;
      --remote)
        if [[ $# -lt 2 || "${2:-}" == -* ]]; then
          bt_err "--remote requires a value"
          return 2
        fi
        remote="${2:-}"
        shift 2
        ;;
      --no-commit) commit=0; shift ;;
      -*)
        bt_err "unknown flag: $1"
        return 2
        ;;
      *)
        feature="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$feature" ]]; then
    bt_err "feature name is required"
    return 2
  fi

  # Ensure BT_PROJECT_ROOT reflects BT_TARGET_DIR / BT_ENV_FILE, and operate within it.
  bt_env_load || true
  [[ -n "${BT_PROJECT_ROOT:-}" ]] || bt_die "missing BT_PROJECT_ROOT"
  cd "$BT_PROJECT_ROOT" || bt_die "failed to cd into BT_PROJECT_ROOT: $BT_PROJECT_ROOT"

  bt_info "shipping feature: $feature"

  # 1. Determine branch and metadata from SPEC.md
  local specs_dir="${BT_SPECS_DIR:-specs}"
  local spec_file="$specs_dir/$feature/SPEC.md"
  local branch="feat/$feature"
  local repo=""
  local issue=""

  if [[ -f "$spec_file" ]]; then
    local b
    b="$(awk -F': *' '$1=="branch"{print $2; exit}' "$spec_file" | tr -d '\r')"
    local r
    r="$(awk -F': *' '$1=="repo"{print $2; exit}' "$spec_file" | tr -d '\r')"
    local i
    i="$(awk -F': *' '$1=="issue"{print $2; exit}' "$spec_file" | tr -d '\r')"
    [[ -n "${b:-}" ]] && branch="$b"
    [[ -n "${r:-}" ]] && repo="$r"
    [[ -n "${i:-}" ]] && issue="$i"
  fi

  # 2. Fail-loud preflight for unstaged expected files (before tests/commit flow).
  if [[ "$commit" == "1" ]]; then
    local unstaged=""
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      unstaged="$(git ls-files --others --modified --exclude-standard -- tests lib commands scripts 2>/dev/null || true)"
    else
      # Outside a git repo, treat present implementation files as unstaged by definition.
      unstaged="$(find tests lib commands scripts -type f 2>/dev/null | LC_ALL=C sort || true)"
    fi
    if [[ -n "$unstaged" ]]; then
      bt_err "Found unstaged files that might be required for this feature:"
      printf '%s\n' "$unstaged" >&2
      bt_die "Abort: ship requires all feature files to be staged. Use git add and try again."
    fi
  fi

  if [[ "$run_mode" == "dry-run" ]]; then
    if [[ -z "$base" ]]; then
      if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local ref
        ref="$(git symbolic-ref -q "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
        if [[ -n "$ref" ]]; then
          base="${ref##*/}"
        else
          base="main"
        fi
      else
        base="main"
      fi
    fi

    local title="feat: $feature"
    local body="Feature: $feature"
    [[ -n "$repo" && -n "$issue" ]] && body+=$'\n'"Issue: https://github.com/$repo/issues/$issue"
    [[ -f "$spec_file" ]] && body+=$'\n'"Spec: $spec_file"

    bt_info "[dry-run] git push -u $remote $branch"
    bt_info "[dry-run] gh pr create --head $branch --base $base --title $title --body $body"
    local artifacts_preview
    artifacts_preview="$(mktemp "${TMPDIR:-/tmp}/bt-pr-artifacts-preview.XXXXXX")"
    bt_pr_write_artifacts_comment "$feature" "$specs_dir" "$artifacts_preview"
    bt_info "[dry-run] Artifacts comment would contain:"
    cat "$artifacts_preview"
    rm -f "$artifacts_preview"
    bt_info "ship complete for $feature"
    return 0
  fi

  # 3. Run tests & lint (run mode only)
  bt_info "running tests..."
  npm test
  bt_info "running lint..."
  npm run lint

  # 4. Create branch if needed
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    bt_info "branch $branch already exists, checking it out..."
    git checkout "$branch"
  else
    bt_info "creating and checking out branch $branch..."
    git checkout -b "$branch"
  fi

  # 4. Commit changes if requested
  if [[ "$commit" == "1" ]]; then
    bt_info "committing changes..."
    # Add SPEC.md and any tests/implementations related to this feature
    # We use explicit paths to avoid staging unrelated items
    local paths_to_add=()
        local unstaged
    unstaged="$(git status --porcelain -- tests lib commands scripts 2>/dev/null || true)"
    if [[ -n "$unstaged" ]]; then
      bt_err "Found unstaged files that might be required for this feature:"
      printf '%s\n' "$unstaged" >&2
      bt_die "Abort: ship requires all feature files to be staged. Use git add and try again."
    fi

    if ! git diff --cached --quiet; then
      git commit -m "feat($feature): ship implementation"
    else
      bt_info "nothing to commit"
    fi
  fi

  # 5. Push
  bt_info "pushing to $remote/$branch..."
  if [[ "$run_mode" == "run" ]]; then
    git push -u "$remote" "$branch"
  else
    bt_info "[dry-run] git push -u $remote $branch"
  fi

  # 6. Open PR via gh
  if [[ -z "$base" ]]; then
    local ref
    ref="$(git symbolic-ref -q "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
    if [[ -n "$ref" ]]; then
      # refs/remotes/<remote>/<branch> -> <branch>
      base="${ref##*/}"
    else
      base="main"
    fi
  fi

  local title="feat: $feature"
  local body="Feature: $feature"
  [[ -n "$repo" && -n "$issue" ]] && body+=$'\n'"Issue: https://github.com/$repo/issues/$issue"
  [[ -f "$spec_file" ]] && body+=$'\n'"Spec: $spec_file"

  bt_info "opening PR on $base..."
  local pr_args=(pr create --head "$branch" --base "$base" --title "$title" --body "$body")
  [[ "$draft" == "1" ]] && pr_args+=(--draft)

  if [[ "$run_mode" == "run" ]]; then
    local pr_out
    pr_out="$(gh "${pr_args[@]}")"
    # gh pr create typically prints the PR URL on success.
    local pr_url
    pr_url="$(printf '%s\n' "$pr_out" | tail -n 1 | tr -d '\r')"
    if [[ -n "$pr_url" ]]; then
      bt_info "posting artifacts comment..."
      local comment_file
      comment_file="$(mktemp "${TMPDIR:-/tmp}/bt-pr-comment.XXXXXX")"
      bt_pr_write_artifacts_comment "$feature" "$specs_dir" "$comment_file"
      gh pr comment "$pr_url" --body-file "$comment_file"
      rm -f "$comment_file"
    else
      bt_err "gh pr create did not return a PR URL; skipping artifacts comment"
    fi
  else
    bt_info "[dry-run] gh ${pr_args[*]}"
    local artifacts_preview
    artifacts_preview="$(mktemp "${TMPDIR:-/tmp}/bt-pr-artifacts-preview.XXXXXX")"
    bt_pr_write_artifacts_comment "$feature" "$specs_dir" "$artifacts_preview"
    bt_info "[dry-run] Artifacts comment would contain:"
    cat "$artifacts_preview"
    rm -f "$artifacts_preview"
  fi

  bt_info "ship complete for $feature"
}
