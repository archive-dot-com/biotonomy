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
      --base) base="${2:-}"; shift 2 ;;
      --remote) remote="${2:-}"; shift 2 ;;
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

  bt_info "shipping feature: $feature"

  # 1. Run Tests & Lint
  bt_info "running tests..."
  npm test
  bt_info "running lint..."
  npm run lint

  # 2. Determine branch and metadata from SPEC.md
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

  # 3. Create branch if needed
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
    [[ -d "$specs_dir/$feature" ]] && paths_to_add+=("$specs_dir/$feature")
    [[ -d "tests" ]] && paths_to_add+=("tests")
    [[ -d "lib" ]] && paths_to_add+=("lib")
    [[ -d "commands" ]] && paths_to_add+=("commands")
    [[ -d "scripts" ]] && paths_to_add+=("scripts")
    
    if [[ ${#paths_to_add[@]} -gt 0 ]]; then
       git add "${paths_to_add[@]}"
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
      base="\${ref##*/}"
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
    gh "\${pr_args[@]}"
  else
    bt_info "[dry-run] gh \${pr_args[*]}"
  fi

  bt_info "ship complete for $feature"
}
